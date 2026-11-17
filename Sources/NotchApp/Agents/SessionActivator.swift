import AppKit
import ApplicationServices
import Darwin

/// Переход к сессии по клику.
///
/// Задача — попасть **в тот самый чат**, а не показать папку в Finder.
///
/// Что надо знать про среду, иначе код выглядит переусложнённым: у десктопного
/// Claude Code все чаты живут строками сайдбара внутри одного окна, и ссылки на
/// конкретную сессию не существует — `claude://code/new` открывает новый чат,
/// а не старый (запрос: anthropics/claude-code#50345). Поэтому единственный
/// точный путь — Accessibility: активировать приложение и нажать нужную строку.
/// Остальное — деградация по ступеням:
/// 1. известен PID — сессия в терминале, поднимаемся по дереву процессов;
/// 2. приложение запущено — активируем и жмём строку сессии;
/// 3. приложение не запущено — запускаем и жмём строку, когда поднимется;
/// 4. приложения нет вовсе — пробуем схему `claude://`, потом Finder.
enum SessionActivator {

    /// Известные идентификаторы приложений. Точный список важнее подстроки:
    /// по подстроке «claude» ловится, например, «Claude Code URL Handler».
    private static let bundleIDs: [AgentSource: [String]] = [
        .claude: [
            "com.anthropic.claudefordesktop",
            "com.anthropic.claude",
            "com.anthropic.claude-desktop",
            "com.anthropic.claudecode",
            "com.anthropic.claude-code"
        ],
        .cursor: [
            // У Cursor bundle id не содержит слова «cursor» — отсюда и список.
            "com.todesktop.230313mzl4w4u92"
        ]
    ]

    private static let excludedFragments = ["notchapp", "urlhandler", "url-handler", "url handler"]

    /// Диалог выдачи Accessibility показываем один раз за запуск: он модальный
    /// и раздражает сильнее, чем польза от повтора.
    private static var trustRequested = false

    // MARK: - Точка входа

    static func activate(_ session: AgentSession) {
        switch session.source {
        case .cloud:  return
        case .claude: activateClaude(session)
        case .cursor: activateCursor(session)
        }
    }

    private static func activateClaude(_ session: AgentSession) {
        if let pid = session.pid, raiseProcessTree(pid: pid, session: session) { return }

        if let app = runningApp(for: .claude) {
            focus(app: app, session: session)
            return
        }

        launchClaude(session)
    }

    private static func activateCursor(_ session: AgentSession) {
        if let app = runningApp(for: .cursor) {
            focus(app: app, session: session)
            return
        }

        let path = session.projectPath
        DispatchQueue.global(qos: .userInitiated).async {
            if let launchPath = Shell.which("cursor") {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: launchPath)
                process.arguments = ["-r", path]
                process.environment = Shell.environment()
                try? process.run()
                return
            }
            Shell.open(["-a", "Cursor", path])
        }
    }

    // MARK: - Активация приложения

    private static func focus(app: NSRunningApplication, session: AgentSession) {
        app.activate()

        // Жать строку списка можно только в Claude: у Cursor чаты не выставлены
        // в Accessibility отдельными элементами, и клик наугад в чужом
        // редакторе — плохая идея. У терминала строк тем более нет.
        let selectRow = isClaude(app)
        let pid = app.processIdentifier

        // Дереву AX нужно мгновение после активации. Всё дальше — в фоне:
        // обход чужого дерева это сотни синхронных запросов в другой процесс,
        // на главном потоке он морозит панель.
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.3) {
            select(session, pid: pid, selectRow: selectRow)
        }
    }

    private static func launchClaude(_ session: AgentSession) {
        guard let url = applicationURL(for: .claude) else {
            DispatchQueue.main.async { openDeepLink(folder: session.projectPath) }
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
            guard let app, error == nil else {
                DispatchQueue.main.async { openDeepLink(folder: session.projectPath) }
                return
            }

            let pid = app.processIdentifier
            // Холодный старт Electron: сайдбар появляется не сразу, поэтому
            // и пауза больше, и попыток больше.
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 2.0) {
                select(session, pid: pid, selectRow: true, attempts: 8)
            }
        }
    }

    /// `claude://code/new?folder=…` открывает **новую** сессию в нужной папке.
    /// Это не тот же чат, поэтому только последний резерв — когда приложения
    /// не нашлось ни среди запущенных, ни на диске.
    private static func openDeepLink(folder: String) {
        guard !folder.isEmpty else { return }

        var components = URLComponents()
        components.scheme = "claude"
        components.host = "code"
        components.path = "/new"
        components.queryItems = [URLQueryItem(name: "folder", value: folder)]

        guard let url = components.url else { return }
        if !NSWorkspace.shared.open(url) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder)])
        }
    }

    // MARK: - Поиск приложения

    private static func isClaude(_ app: NSRunningApplication) -> Bool {
        let identifier = app.bundleIdentifier?.lowercased() ?? ""
        let name = (app.localizedName ?? "").lowercased()

        guard !excludedFragments.contains(where: { identifier.contains($0) || name.contains($0) }) else {
            return false
        }
        if (bundleIDs[.claude] ?? []).contains(where: { $0.lowercased() == identifier }) { return true }
        return identifier.contains("claude") || name.contains("claude")
    }

    private static func runningApp(for source: AgentSource) -> NSRunningApplication? {
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        let identifiers = bundleIDs[source] ?? []

        if let match = running.first(where: { app in
            guard let identifier = app.bundleIdentifier?.lowercased() else { return false }
            return identifiers.contains(where: { $0.lowercased() == identifier })
        }) {
            return match
        }

        // Резерв: сборки бывают разные (бета, ранний доступ, свой билд).
        let needle = source.rawValue
        return running.first { app in
            let identifier = app.bundleIdentifier?.lowercased() ?? ""
            let name = (app.localizedName ?? "").lowercased()
            guard !excludedFragments.contains(where: { identifier.contains($0) || name.contains($0) }) else {
                return false
            }
            return identifier.contains(needle) || name.contains(needle)
        }
    }

    private static func applicationURL(for source: AgentSource) -> URL? {
        for identifier in bundleIDs[source] ?? [] {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
                return url
            }
        }

        let name = source == .claude ? "Claude" : "Cursor"
        for directory in ["/Applications", Paths.home.appendingPathComponent("Applications").path] {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent("\(name).app")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    // MARK: - Выбор сессии внутри приложения

    /// Поднять окно сессии и, если можно, нажать её строку в сайдбаре.
    /// Вызывать только из фонового потока.
    private static func select(_ session: AgentSession, pid: pid_t, selectRow: Bool, attempts: Int = 4) {
        guard ensureTrust() else { return }

        let application = AXUIElementCreateApplication(pid)
        AX.setTimeout(application, seconds: 1.5)
        // Electron строит дерево AX только по явной просьбе — без этого у
        // приложения видны одни окна и ни одной строки внутри них.
        AX.enableElectronAccessibility(application)

        raiseWindow(application: application, keys: session.matchKeys)

        // Ключи короче четырёх символов не годятся для поиска строки: проект
        // с именем «ai» совпадёт с «Main», «Details» и половиной интерфейса.
        let keys = session.matchKeys.filter { $0.count >= 4 }
        guard selectRow, !keys.isEmpty else { return }

        for attempt in 0..<attempts {
            if attempt > 0 { Thread.sleep(forTimeInterval: 0.4) }
            if pressRow(application: application, session: session, keys: keys) { return }
        }

        Log.agents.notice("строку чата не нашёл — приложение поднято, выбирать вручную")
    }

    private static func ensureTrust() -> Bool {
        if AX.isTrusted { return true }

        if !trustRequested {
            trustRequested = true
            DispatchQueue.main.async { AX.requestTrust() }
        }
        Log.agents.notice("нет Accessibility: приложение поднято, до чата не дошёл")
        return false
    }

    private static func raiseWindow(application: AXUIElement, keys: [String]) {
        guard !keys.isEmpty else { return }

        for key in keys {
            guard let window = AX.windows(of: application).first(where: {
                AX.label($0).localizedCaseInsensitiveContains(key)
            }) else { continue }
            AX.raise(window)
            return
        }
    }

    /// Нажать строку сессии в списке.
    ///
    /// Границы намеренно узкие: ищем внутри контейнера-списка, жмём только то,
    /// по чему вообще принято кликать, и не трогаем длинные тексты — имя
    /// проекта встречается и в сообщениях чата, и в заголовках вкладок.
    private static func pressRow(application: AXUIElement, session: AgentSession, keys: [String]) -> Bool {
        for window in AX.windows(of: application) {
            let list = AX.firstMatch(in: window, maxDepth: 14, limit: 1200) { element in
                AX.containerRoles.contains(AX.role(element))
            }

            // Списка не нашлось — ищем по всему окну, но тогда только по имени
            // воркtree: оно уникально, а имя проекта — нет.
            let root = list ?? window
            let allowed = list != nil ? keys : keys.filter { $0 == session.worktreeName }
            guard !allowed.isEmpty else { continue }

            for key in allowed {
                let hit = AX.firstMatch(in: root, maxDepth: 14, limit: 1500) { element in
                    let text = AX.label(element)
                    guard !text.isEmpty, text.count <= 80 else { return false }
                    guard text.localizedCaseInsensitiveContains(key) else { return false }
                    return AX.actionable(from: element) != nil
                }

                guard let hit, let target = AX.actionable(from: hit) else { continue }
                if AX.press(target) {
                    Log.agents.notice("перешёл в чат по строке «\(AX.label(target), privacy: .public)»")
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Терминальные сессии

    /// Поднимаемся от процесса сессии вверх по дереву до первого настоящего
    /// приложения — это и есть терминал или IDE, в котором живёт чат.
    private static func raiseProcessTree(pid: pid_t, session: AgentSession) -> Bool {
        var current = pid

        for _ in 0..<10 {
            if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy == .regular {
                focus(app: app, session: session)
                return true
            }
            guard let parent = parentPID(of: current), parent > 1 else { break }
            current = parent
        }
        return false
    }

    private static func parentPID(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]

        let result = mib.withUnsafeMutableBufferPointer { buffer -> Int32 in
            sysctl(buffer.baseAddress, UInt32(buffer.count), &info, &size, nil, 0)
        }

        guard result == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

    // MARK: - Диагностика

    /// Снимок того, что мы видим в чужом приложении. Нужен один раз — чтобы
    /// подобрать правило поиска строки чата по факту, а не по догадке.
    static func diagnostics(for source: AgentSource) -> String {
        var report: [String] = []
        report.append("Accessibility: \(AX.isTrusted ? "выдан" : "НЕ выдан")")

        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .map { "\($0.localizedName ?? "?") — \($0.bundleIdentifier ?? "нет id")" }
        report.append("Запущенные приложения:\n  " + running.joined(separator: "\n  "))

        guard let app = runningApp(for: source) else {
            report.append("Приложение источника \(source.title) не найдено среди запущенных.")
            return report.joined(separator: "\n\n")
        }

        report.append("Источник: \(app.localizedName ?? "?") — \(app.bundleIdentifier ?? "нет id")")

        guard AX.isTrusted else {
            AX.requestTrust()
            report.append("Нет доступа Accessibility — выдайте его и повторите.")
            return report.joined(separator: "\n\n")
        }

        let element = AXUIElementCreateApplication(app.processIdentifier)
        AX.setTimeout(element, seconds: 2)
        AX.enableElectronAccessibility(element)
        report.append("Дерево:\n" + AX.dump(element))

        return report.joined(separator: "\n\n")
    }
}
