import SwiftUI

/// Откуда пришла сессия.
enum AgentSource: String, CaseIterable, Codable, Hashable {
    case claude
    case cursor
    case cloud

    var title: String {
        switch self {
        case .claude: return "Claude Code"
        case .cursor: return "Cursor"
        case .cloud:  return "Cloud"
        }
    }
}

/// Состояния зафиксированы как контракт и совпадают с клиентом для Windows и Linux.
enum AgentState: String, Codable, Hashable {
    case working
    case waitingPermission
    case waitingInput
    case done
    case error

    var title: String {
        switch self {
        case .working:           return "работает"
        case .waitingPermission: return "ждёт разрешения"
        case .waitingInput:      return "ждёт ответа"
        case .done:              return "готово"
        case .error:             return "ошибка"
        }
    }

    /// Цвет состояния — основа всей подсветки: он идёт и в строку, и в ауру.
    var color: Color {
        switch self {
        case .working:           return Color(red: 0.36, green: 0.62, blue: 1.00)
        case .waitingPermission: return Color(red: 1.00, green: 0.62, blue: 0.20)
        case .waitingInput:      return Color(red: 1.00, green: 0.84, blue: 0.28)
        case .done:              return Color(red: 0.35, green: 0.83, blue: 0.50)
        case .error:             return Color(red: 1.00, green: 0.38, blue: 0.36)
        }
    }

    /// Значок состояния для закрытой челки: в крыле шириной 40 pt текст не
    /// читается, а форма — читается.
    var mark: String {
        switch self {
        case .working:           return "circle.dotted"
        case .waitingPermission: return "hand.raised.fill"
        case .waitingInput:      return "questionmark"
        case .done:              return "checkmark"
        case .error:             return "exclamationmark"
        }
    }

    /// Порядок сортировки: то, что ждёт человека, всегда сверху.
    var priority: Int {
        switch self {
        case .waitingPermission: return 0
        case .waitingInput:      return 1
        case .working:           return 2
        case .error:             return 3
        case .done:              return 4
        }
    }
}

struct AgentSession: Identifiable, Equatable, Codable {
    let id: String
    var sessionId: String
    var source: AgentSource
    var state: AgentState
    var cwd: String
    var detail: String?
    var pid: Int32?
    var updatedAt: Date
    /// Время последнего события от хука. При расхождении с опросом приоритет
    /// у хука моложе двух секунд.
    var lastHookAt: Date?
    /// Путь к стенограмме из payload хука: по нему достаётся человекочитаемый
    /// заголовок чата, когда понадобится точное сопоставление со списком в IDE.
    var transcriptPath: String? = nil
    /// Когда в сессию перешли по клику. Пока `nil`, завершённая сессия остаётся
    /// в челке — в этом весь смысл: «готово» не должно гаснуть само.
    var visitedAt: Date? = nil
    /// Пришёл `SessionEnd`: чат закрыт, но переход в него ещё не совершали.
    var hasEnded: Bool = false

    var requiresAttention: Bool {
        state == .waitingPermission || state == .waitingInput
    }

    /// Закончила работу, но в неё ещё не заходили.
    var awaitsVisit: Bool {
        state == .done && visitedAt == nil
    }

    /// Путь проекта.
    ///
    /// У сессий десктопного Claude Code `cwd` — это воркtree внутри проекта
    /// (`<проект>/.claude/worktrees/<имя>`). Показывать надо проект, иначе
    /// в списке будут одинаковые «worktrees» вместо названий.
    var projectPath: String {
        guard let range = cwd.range(of: "/.claude/worktrees/") else { return cwd }
        return String(cwd[cwd.startIndex..<range.lowerBound])
    }

    /// Имя воркtree — самый близкий к названию сессии текст, который у нас есть.
    var worktreeName: String? {
        guard let range = cwd.range(of: "/.claude/worktrees/") else { return nil }
        let tail = cwd[range.upperBound...]
        guard let first = tail.split(separator: "/").first else { return nil }
        let name = String(first)
        return name.isEmpty ? nil : name
    }

    /// Имя папки проекта — то, по чему сессию узнают глазами.
    var title: String {
        let name = (projectPath as NSString).lastPathComponent
        return name.isEmpty ? sessionId : name
    }

    /// Строки, по которым ищем сессию в чужом интерфейсе: сперва самая частная,
    /// потом самая общая.
    var matchKeys: [String] {
        var keys: [String] = []
        if let worktreeName { keys.append(worktreeName) }
        let project = title
        if !project.isEmpty, !keys.contains(project) { keys.append(project) }
        return keys
    }

    static func makeID(source: AgentSource, sessionId: String) -> String {
        "\(source.rawValue):\(sessionId)"
    }
}

struct HookStatus: Equatable {
    var claude = false
    var cursor = false
}
