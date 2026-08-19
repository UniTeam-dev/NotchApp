import Foundation

/// Запуск внешних команд. Отсутствие `claude` или `media-control` — это норма,
/// а не сбой, поэтому наружу отдаём nil, а не бросаем.
enum Shell {
    /// `Process` не наследует PATH логин-шелла, когда приложение запущено из Finder,
    /// поэтому ищем бинари руками по типовым каталогам.
    static let searchPaths: [String] = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        Paths.home.appendingPathComponent(".local/bin").path,
        Paths.home.appendingPathComponent(".bun/bin").path,
        Paths.home.appendingPathComponent(".npm-global/bin").path
    ]

    static func which(_ name: String) -> String? {
        for dir in searchPaths {
            let candidate = (dir as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
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
