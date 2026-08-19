import Foundation

/// Все пути приложения в одном месте.
///
/// Отдельно живут два каталога:
/// - `support` — данные приложения (полка, инбокс) в Application Support;
/// - `scriptHome` — каталог скриптов-хуков, `~/.notchapp`. Он вынесен из
///   Application Support сознательно: путь скрипта попадает в чужие конфиги
///   (`~/.claude/settings.json`, `~/.cursor/hooks.json`) и обязан быть без пробелов,
///   а имя пользователя в «Application Support» пробелы содержать может.
enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser

    static var support: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("NotchApp", isDirectory: true)
    }

    /// Копии файлов, брошенных на полку.
    static var shelf: URL { support.appendingPathComponent("shelf", isDirectory: true) }

    /// Куда хуки складывают payload'ы.
    static var inbox: URL { support.appendingPathComponent("inbox", isDirectory: true) }

    /// Каталог скриптов — путь без пробелов, потому что уезжает в чужие конфиги.
    static var scriptHome: URL { home.appendingPathComponent(".notchapp", isDirectory: true) }

    static var hookScript: URL { scriptHome.appendingPathComponent("notch-hook.sh") }

    static var claudeSettings: URL { home.appendingPathComponent(".claude/settings.json") }
    static var cursorHooks: URL { home.appendingPathComponent(".cursor/hooks.json") }

    static func ensureDirectories() {
        for url in [support, shelf, inbox, scriptHome] {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
