import Foundation

/// Запуск внешних команд. Отсутствие `claude` или `media-control` — это норма,
/// а не сбой, поэтому наружу отдаём nil, а не бросаем.
enum Shell {
    /// Приложение, запущенное из Finder, наследует куцый системный PATH, а не
    /// тот, что настроен в профиле шелла. Поэтому сначала смотрим типовые
    /// каталоги руками, а если не нашли — спрашиваем сам логин-шелл.
    static let searchPaths: [String] = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        Paths.home.appendingPathComponent(".local/bin").path,
        Paths.home.appendingPathComponent(".bun/bin").path,
        Paths.home.appendingPathComponent(".npm-global/bin").path,
        Paths.home.appendingPathComponent(".claude/local").path,
        Paths.home.appendingPathComponent(".volta/bin").path,
        Paths.home.appendingPathComponent(".cargo/bin").path
    ]

    private static let cacheLock = NSLock()
    private static var cache: [String: String?] = [:]

    static func which(_ name: String) -> String? {
        cacheLock.lock()
        if let cached = cache[name] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let found = lookupInSearchPaths(name) ?? lookupViaLoginShell(name)

        cacheLock.lock()
        cache[name] = found
        cacheLock.unlock()

        if found == nil {
            Log.notch.notice("не нашёл бинарь \(name, privacy: .public)")
        }
        return found
    }

    /// Сбросить кэш — например, после того как пользователь поставил `claude`
    /// уже при работающем приложении.
    static func forgetLookups() {
        cacheLock.lock()
        cache.removeAll()
        cacheLock.unlock()
    }

    private static func lookupInSearchPaths(_ name: String) -> String? {
        for dir in searchPaths {
            let candidate = (dir as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    /// Спрашиваем логин-шелл: он прочитает профиль пользователя и найдёт то,
    /// что лежит в nvm, asdf, mise и прочих менеджерах версий.
    private static func lookupViaLoginShell(_ name: String) -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard FileManager.default.isExecutableFile(atPath: shell) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lc", "command -v \(name)"]
        // PATH здесь намеренно НЕ подменяем: весь смысл в том, чтобы шелл
        // собрал его сам из профиля.

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let deadline = Date().addingTimeInterval(6)
        DispatchQueue.global(qos: .utility).async {
            while Date() < deadline, process.isRunning {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning { process.terminate() }
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")
            .last?
            .trimmingCharacters(in: .whitespaces)

        guard let path, !path.isEmpty,
              FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return path
    }

    static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = searchPaths.joined(separator: ":")
        return env
    }

    /// Синхронный запуск с мягким таймаутом. Возвращает stdout или nil.
    @discardableResult
    static func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval = 5) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.environment = environment()

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        // Сторож: если процесс завис, снимаем его, чтобы чтение ниже разблокировалось.
        let deadline = Date().addingTimeInterval(timeout)
        DispatchQueue.global(qos: .utility).async {
            while Date() < deadline, process.isRunning {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning { process.terminate() }
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    /// Открыть приложение или URL, ничего не дожидаясь.
    static func open(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments
        try? process.run()
    }
}
