import Foundation

/// Чтение системного Now Playing через CLI `media-control`.
///
/// Почему не напрямую: с macOS 15.4 `MRMediaRemoteGetNowPlayingInfo` для
/// сторонних процессов пуст. `media-control` читает MediaRemote внутри
/// `/usr/bin/perl` — платформенного бинаря Apple, чей bundle ID проходит гейт
/// `mediaremoted`. Это единственный рабочий путь к метаданным.
///
/// Ставится так: `brew install media-control`.
final class MediaControlBridge {
    /// Отдаёт уже смерженный снимок: поток присылает и полные объекты, и диффы.
    var onSnapshot: (([String: Any]) -> Void)?

    private var process: Process?
    private var buffer = Data()
    private var merged: [String: Any] = [:]
    private var shouldRun = false
    private let queue = DispatchQueue(label: "com.notchapp.media-control")

    static var isAvailable: Bool { Shell.which("media-control") != nil }

    func start() {
        shouldRun = true
        launch()
    }

    func stop() {
        shouldRun = false
        process?.terminate()
        process = nil
    }

    private func launch() {
        guard shouldRun, let binary = Shell.which("media-control") else { return }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: binary)
        // Обложку из потока исключаем: она прилетает base64 на каждом тике и
        // раздувает трафик. Её забираем отдельно, по смене трека.
        task.arguments = ["stream", "--no-artwork"]
        task.environment = Shell.environment()

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            self?.queue.async { self?.consume(chunk) }
        }

        task.terminationHandler = { [weak self] _ in
            guard let self, self.shouldRun else { return }
            // Поток иногда обрывается сам — поднимаем обратно с паузой.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.launch() }
        }

        do {
            try task.run()
            process = task
        } catch {
            Log.music.error("media-control не запустился: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func consume(_ chunk: Data) {
        buffer.append(chunk)

        let newline = UInt8(ascii: "\n")
        while let index = buffer.firstIndex(of: newline) {
            let line = buffer[buffer.startIndex..<index]
            buffer.removeSubrange(buffer.startIndex...index)
            guard !line.isEmpty else { continue }
            handle(line: Data(line))
        }

        // Страховка от мусора: не копим бесконечно, если переводов строки нет.
        if buffer.count > 1_000_000 { buffer.removeAll() }
    }

    private func handle(line: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }

        // Поток отдаёт либо объект целиком, либо конверт с полем payload.
        let payload = (object["payload"] as? [String: Any]) ?? object
        guard !payload.isEmpty else { return }

        for (key, value) in payload {
            merged[key] = value
        }
        let snapshot = merged

        DispatchQueue.main.async { [weak self] in
            self?.onSnapshot?(snapshot)
        }
    }

    /// Разовый запрос с обложкой — зовём по смене трека, не по таймеру.
    func fetchArtwork(completion: @escaping (Data?) -> Void) {
        guard let binary = Shell.which("media-control") else {
            completion(nil)
            return
        }

        DispatchQueue.global(qos: .utility).async {
            let output = Shell.run(binary, ["get"], timeout: 4)
            guard
                let data = output?.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let payload = (object["payload"] as? [String: Any]) ?? object
            let base64 = (payload["artworkData"] as? String) ?? (payload["artwork"] as? String)
            let artwork = base64.flatMap { Data(base64Encoded: $0) }

            DispatchQueue.main.async { completion(artwork) }
        }
    }
}
