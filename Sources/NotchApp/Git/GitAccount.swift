import Foundation

/// Аккаунт из `gh auth status`.
struct GitAccount: Identifiable, Hashable {
    let host: String
    let login: String
    var isActive = false
    /// `false` — gh знает аккаунт, но токен протух или отозван.
    var isValid = true
    var gitProtocol: String?
    var scopes: [String] = []
    /// Где лежит токен: keyring, GH_TOKEN, файл конфига.
    var storage: String?

    var id: String { host + "/" + login }

    var avatarURL: URL? {
        let base = host == "github.com" ? "https://github.com" : "https://\(host)"
        return URL(string: "\(base)/\(login).png?size=64")
    }

    var profileURL: URL? {
        URL(string: "https://\(host)/\(login)")
    }
}

/// Подпись коммитов: `user.name` и `user.email`.
struct GitIdentity: Codable, Hashable {
    var name: String
    var email: String

    var display: String { "\(name) <\(email)>" }

    var isEmpty: Bool {
        name.trimmingCharacters(in: .whitespaces).isEmpty
            || email.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

/// Разбор человекочитаемого вывода `gh auth status`.
///
/// JSON у этой команды появился не во всех версиях gh, поэтому читаем текст.
/// Понимаем оба формата: новый (`account X`, несколько аккаунтов на хост,
/// строка `Active account`) и старый (`as X`, один аккаунт).
enum GhAuthParser {
    private static let accountLine = try? NSRegularExpression(
        pattern: #"(Logged in to|Failed to log in to) (\S+) (?:account|as) (\S+)(?: \(([^)]+)\))?"#
    )
    private static let quoted = try? NSRegularExpression(pattern: #"'([^']+)'"#)

    static func parse(_ text: String) -> [GitAccount] {
        var accounts: [GitAccount] = []
        var sawActiveFlag: Set<String> = []

        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if let groups = match(accountLine, in: line) {
                var account = GitAccount(host: groups[1] ?? "github.com", login: groups[2] ?? "?")
                account.isValid = groups[0] == "Logged in to"
                account.storage = groups[3]
                accounts.append(account)
                continue
            }

            guard !accounts.isEmpty else { continue }
            let last = accounts.count - 1

            if line.hasPrefix("- Active account:") {
                accounts[last].isActive = line.hasSuffix("true")
                sawActiveFlag.insert(accounts[last].host)
            } else if line.hasPrefix("- Git operations protocol:") {
                accounts[last].gitProtocol = value(after: ":", in: line)
            } else if line.hasPrefix("- Token scopes:") {
                accounts[last].scopes = allMatches(quoted, in: line)
            }
        }

        // Старый gh не пишет Active account: единственный аккаунт хоста и есть активный.
        for index in accounts.indices where !sawActiveFlag.contains(accounts[index].host) {
            let sameHost = accounts.filter { $0.host == accounts[index].host }
            if sameHost.count == 1 { accounts[index].isActive = accounts[index].isValid }
        }

        return accounts
    }

    private static func value(after separator: Character, in line: String) -> String? {
        guard let index = line.firstIndex(of: separator) else { return nil }
        let value = line[line.index(after: index)...].trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    /// Группы первого совпадения; отсутствующая группа — nil.
    private static func match(_ regex: NSRegularExpression?, in line: String) -> [String?]? {
        guard let regex else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        guard let result = regex.firstMatch(in: line, range: range) else { return nil }
        return (1..<result.numberOfRanges).map { index in
            Range(result.range(at: index), in: line).map { String(line[$0]) }
        }
    }

    private static func allMatches(_ regex: NSRegularExpression?, in line: String) -> [String] {
        guard let regex else { return [] }
        let range = NSRange(line.startIndex..., in: line)
        return regex.matches(in: line, range: range).compactMap { result in
            Range(result.range(at: 1), in: line).map { String(line[$0]) }
        }
    }
}
