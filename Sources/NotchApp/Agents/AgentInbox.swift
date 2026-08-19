import Foundation

/// Payload одного события хука.
struct HookEvent {
    var source: AgentSource
    var sessionId: String
    var event: String
    var notificationType: String?
    var cwd: String
    var pid: Int32?
    var toolName: String?
}

/// Наблюдение за каталогом инбокса.
///
/// IPC намеренно скучный: скрипт пишет во временный файл и атомарно
/// переименовывает его в `inbox/`. Мы читаем по событию файловой системы плюс
/// страховочный таймер (события ФС теряются при переключении Spaces) и удаляем.
final class AgentInbox {
    var onEvent: ((HookEvent) -> Void)?

    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.notchapp.inbox")

    func start() {
        try? FileManager.default.createDirectory(at: Paths.inbox, withIntermediateDirectories: true)

        descriptor = open(Paths.inbox.path, O_EVTONLY)
        if descriptor >= 0 {
            let watcher = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .extend],
                queue: queue
            )
            watcher.setEventHandler { [weak self] in self?.drain() }
            watcher.resume()
            source = watcher
        }

        let ticker = DispatchSource.makeTimerSource(queue: queue)
        ticker.schedule(deadline: .now() + 1, repeating: 1.5)
        ticker.setEventHandler { [weak self] in self?.drain() }
        ticker.resume()
        timer = ticker
    }

    func stop() {
        source?.cancel()
        source = nil
        timer?.cancel()
        timer = nil
        if descriptor >= 0 {
            close(descriptor)
            descriptor = -1
        }
    }

    private func drain() {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: Paths.inbox.path) else { return }

        // Временный файл лежит в том же каталоге (иначе переименование перестанет
        // быть атомарным), поэтому он тоже виден. Его имя начинается с точки.
        for name in names.sorted() where name.hasSuffix(".json") && !name.hasPrefix(".") {
            let url = Paths.inbox.appendingPathComponent(name)
            defer { try? manager.removeItem(at: url) }

            guard let data = try? Data(contentsOf: url) else { continue }
            guard let event = parse(data: data, fileName: name) else { continue }

            DispatchQueue.main.async { [weak self] in
                self?.onEvent?(event)
            }
        }
    }

    /// Инструмент определяется именем файла, а не полем внутри payload:
    /// наборы событий у Claude Code и Cursor разные, и различать их надо
    /// до разбора. Хирургия над чужим JSON в `sh` ради вставки одного поля —
    /// верный способ однажды сломать разбор на пустом месте.
    private func parse(data: Data, fileName: String) -> HookEvent? {
        let source: AgentSource
        if fileName.hasSuffix(".cursor.json") {
            source = .cursor
        } else if fileName.hasSuffix(".claude.json") {
            source = .claude
        } else {
            return nil
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Log.agents.error("инбокс: не разобрался payload \(fileName, privacy: .public)")
            return nil
        }

        let sessionId = (object["session_id"] as? String)
            ?? (object["sessionId"] as? String)
            ?? (object["conversation_id"] as? String)
            ?? "unknown"

        let event = (object["hook_event_name"] as? String)
            ?? (object["hookEventName"] as? String)
            ?? (object["event"] as? String)
            ?? ""

        let cwd = (object["cwd"] as? String)
            ?? (object["workspace_roots"] as? [String])?.first
            ?? ""

        var pid: Int32?
        if let value = object["pid"] as? Int { pid = Int32(value) }

        return HookEvent(
            source: source,
            sessionId: sessionId,
            event: event,
            notificationType: object["notification_type"] as? String,
            cwd: cwd,
            pid: pid,
            toolName: object["tool_name"] as? String
        )
    }
}
