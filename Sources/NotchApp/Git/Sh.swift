import Foundation

/// Короткие служебные вызовы через логин-шелл — тот же механизм, что у
/// вкладки «Терминал», только без кнопки. Колбэк приходит на главный поток.
enum Sh {
    /// Одинарные кавычки: внутри них шелл не трогает ничего, кроме самих кавычек.
    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func join(_ arguments: [String]) -> String {
        arguments.map(quote).joined(separator: " ")
    }

    static func run(
        _ command: String,
        input: Data? = nil,
        timeout: TimeInterval = 30,
        completion: @escaping (CommandResult) -> Void
    ) {
        let runner = CommandRunner(
            binding: CommandBinding(title: "", command: command),
            input: input
        )
        DispatchQueue.global(qos: .userInitiated).async {
            let result = runner.execute(timeout: timeout)
            DispatchQueue.main.async { completion(result) }
        }
    }
}

extension CommandResult {
    /// Первая содержательная строка — для коротких сообщений об ошибке.
    var firstLine: String {
        output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? "код \(exitCode)"
    }

    /// Шелл не нашёл команду.
    var commandNotFound: Bool {
        exitCode == 127
    }
}
