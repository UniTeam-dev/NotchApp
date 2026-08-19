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

struct AgentSession: Identifiable, Equatable {
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

    var requiresAttention: Bool {
        state == .waitingPermission || state == .waitingInput
    }

    /// Имя папки проекта — то, по чему сессию узнают глазами.
    var title: String {
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? sessionId : name
    }

    static func makeID(source: AgentSource, sessionId: String) -> String {
        "\(source.rawValue):\(sessionId)"
    }
}

struct HookStatus: Equatable {
    var claude = false
    var cursor = false
}
