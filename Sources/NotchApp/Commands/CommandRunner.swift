import Foundation

/// Один запуск одной команды.
///
/// Команда уходит в логин-шелл пользователя (`$SHELL -lc`): приложение,
/// запущенное из Finder, наследует куцый системный PATH, а логин-шелл сам
/// соберёт его из профиля — brew, nvm, mise и прочее окажутся на месте.
/// stdout и stderr сливаются в один поток, как в обычном терминале.
final class CommandRunner {
    /// Сколько вывода держим. Хвост важнее начала, поэтому режем сверху.
    static let outputLimit = 64 * 1024

    private let binding: CommandBinding
    /// Что подать на stdin. `nil` — пустой stdin, команда не сможет ничего спросить.
    private let input: Data?
    private let process = Process()
    private let lock = NSLock()
    private var buffer = Data()
    private var cancelled = false

    init(binding: CommandBinding, input: Data? = nil) {
        self.binding = binding
        self.input = input
    }

    /// Блокирующий запуск — звать только с фоновой очереди.
    /// `timeout == nil` — ждать сколько угодно (фоновые команды).
    func execute(timeout: TimeInterval?) -> CommandResult {
        let started = Date()

        guard let directory = Self.directory(for: binding) else {
            return failure("Нет такого каталога: \(binding.workingDirectory ?? "")", started: started)
        }

        process.executableURL = URL(fileURLWithPath: Self.shell)
        process.arguments = ["-lc", binding.command]
        process.currentDirectoryURL = directory
        process.environment = Self.environment()
        let inputPipe: Pipe? = input == nil ? nil : Pipe()
        if let inputPipe {
            process.standardInput = inputPipe
        } else {
            process.standardInput = FileHandle.nullDevice
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // Читаем по мере поступления: иначе болтливая команда забьёт буфер
        // пайпа и повиснет, так и не дойдя до выхода.
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            self?.append(chunk)
        }

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return failure("Не удалось запустить: \(error.localizedDescription)", started: started)
        }

        if let inputPipe, let input {
            let handle = inputPipe.fileHandleForWriting
            try? handle.write(contentsOf: input)
            try? handle.close()
        }

        // Остановить могли ещё до старта процесса.
        lock.lock()
        let cancelledEarly = cancelled
        lock.unlock()
        if cancelledEarly { stop() }

        var timedOut = false
        if let timeout {
            if exited.wait(timeout: .now() + timeout) == .timedOut {
                timedOut = true
                stop()
                exited.wait()
            }
        } else {
            exited.wait()
        }

        // Даём обработчику дочитать последний кусок.
        Thread.sleep(forTimeInterval: 0.08)
        pipe.fileHandleForReading.readabilityHandler = nil

        lock.lock()
        let data = buffer
        let wasCancelled = cancelled
        lock.unlock()

        return CommandResult(
            output: Self.clean(String(decoding: data, as: UTF8.self)),
            exitCode: process.terminationStatus,
            timedOut: timedOut && !wasCancelled,
            cancelled: wasCancelled,
            finishedAt: Date(),
            duration: Date().timeIntervalSince(started)
        )
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
        stop()
    }

    /// Мягко, потом жёстко. Сначала гасим детей: шелл с конвейером или
    /// `npm run dev` оставил бы их сиротами, держащими порт.
    private func stop() {
        guard process.isRunning else { return }
        let pid = process.processIdentifier

        Self.signalChildren(of: pid, signal: "TERM")
        process.terminate()

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) { [process] in
            guard process.isRunning else { return }
            Self.signalChildren(of: pid, signal: "KILL")
            kill(pid, SIGKILL)
        }
    }

    private static func signalChildren(of pid: Int32, signal: String) {
        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkill.arguments = ["-\(signal)", "-P", String(pid)]
        pkill.standardOutput = FileHandle.nullDevice
        pkill.standardError = FileHandle.nullDevice
        try? pkill.run()
        pkill.waitUntilExit()
    }

    // MARK: - Внутреннее

    private func append(_ chunk: Data) {
        lock.lock()
        buffer.append(chunk)
        if buffer.count > Self.outputLimit * 2 {
            buffer = buffer.suffix(Self.outputLimit)
        }
        lock.unlock()
    }

    private func failure(_ message: String, started: Date) -> CommandResult {
        CommandResult(
            output: message,
            exitCode: -1,
            timedOut: false,
            cancelled: false,
            finishedAt: Date(),
            duration: Date().timeIntervalSince(started)
        )
    }

    static var shell: String {
        if let shell = ProcessInfo.processInfo.environment["SHELL"],
           FileManager.default.isExecutableFile(atPath: shell) {
            return shell
        }
        return "/bin/zsh"
    }

    /// PATH намеренно не трогаем — его соберёт логин-шелл. Цвета гасим:
    /// escape-последовательности в кнопке превращаются в мусор.
    private static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "dumb"
        env["NO_COLOR"] = "1"
        env["CLICOLOR"] = "0"
        env["PAGER"] = "cat"
        env["GIT_PAGER"] = "cat"
        return env
    }

    static func directory(for binding: CommandBinding) -> URL? {
        let raw = binding.workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return Paths.home }

        let expanded = (raw as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    /// Вырезаем ANSI-последовательности, которые всё же просочились.
    private static let ansi = try? NSRegularExpression(pattern: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]")

    private static func clean(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "\r\n", with: "\n")
        if let ansi {
            let range = NSRange(result.startIndex..., in: result)
            result = ansi.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
