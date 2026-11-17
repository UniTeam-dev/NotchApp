import Foundation

/// Привязанная команда — одна кнопка на вкладке «Терминал».
struct CommandBinding: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    /// Краткое описание. Оно же подпись кнопки.
    var title: String
    /// Строка для шелла — ровно так, как её набрали бы в терминале.
    var command: String
    /// Каталог запуска. `nil` — домашний.
    var workingDirectory: String? = nil
    /// Долгоживущая команда (`caffeinate`, dev-сервер): без таймаута, живёт,
    /// пока её не остановят. Опциональные поля — чтобы старый commands.json
    /// читался без миграции.
    var background: Bool? = nil
    /// Запускать фоновую команду вместе с NotchApp.
    var autostart: Bool? = nil

    var isBackground: Bool { background ?? false }
    var startsWithApp: Bool { isBackground && (autostart ?? false) }
}

/// Итог последнего запуска.
struct CommandResult: Hashable {
    let output: String
    let exitCode: Int32
    let timedOut: Bool
    let cancelled: Bool
    let finishedAt: Date
    let duration: TimeInterval

    var succeeded: Bool { exitCode == 0 && !timedOut && !cancelled }

    /// Что показать в самой кнопке.
    ///
    /// При успехе — хвост вывода: у большинства команд результат в конце.
    /// При ошибке — начало: CLI сначала пишут причину, а потом простыню
    /// справки, и хвост у такой ошибки бесполезен.
    func summary(lines: Int = 3) -> String {
        if cancelled { return "Остановлено" }
        if timedOut { return "Не уложилась в таймаут" }

        let nonEmpty = output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let picked = succeeded ? Array(nonEmpty.suffix(lines)) : Array(nonEmpty.prefix(lines))
        if !picked.isEmpty { return picked.joined(separator: "\n") }
        return succeeded ? "Готово, вывода нет" : "Код выхода \(exitCode)"
    }
}

enum CommandRunState: Hashable {
    case idle
    case running(since: Date)
    case finished(CommandResult)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    var result: CommandResult? {
        if case .finished(let result) = self { return result }
        return nil
    }
}
