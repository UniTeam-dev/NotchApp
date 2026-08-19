import Foundation

/// Опрос `claude agents --json --all`.
///
/// Хуки реагируют мгновенно, но видят только те сессии, что стартовали после
/// установки. Опрос даёт официальный список живых сессий, в том числе начатых
/// до запуска приложения.
enum ClaudeAgentsProbe {
    struct Row {
        var sessionId: String
        var cwd: String
        var state: AgentState
        var detail: String?
        var pid: Int32?
    }

    static var isAvailable: Bool { Shell.which("claude") != nil }

    static func poll() -> [Row] {
        guard let claude = Shell.which("claude") else { return [] }
        guard let output = Shell.run(claude, ["agents", "--json", "--all"], timeout: 4) else { return [] }
        guard let data = output.data(using: .utf8) else { return [] }

        // Формат менялся: встречается и голый массив, и объект с полем agents.
        let rawRows: [[String: Any]]
        if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            rawRows = array
        } else if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let array = object["agents"] as? [[String: Any]] {
            rawRows = array
        } else {
            return []
        }

        return rawRows.compactMap(row(from:))
    }

    private static func row(from raw: [String: Any]) -> Row? {
        let sessionId = (raw["sessionId"] as? String) ?? (raw["id"] as? String)
        guard let sessionId else { return nil }

        let cwd = (raw["cwd"] as? String) ?? ""
        let waitingFor = raw["waitingFor"] as? String

        var pid: Int32?
        if let value = raw["pid"] as? Int { pid = Int32(value) }

        let state = mapState(
            status: raw["status"] as? String,
            backgroundState: raw["state"] as? String,
            waitingFor: waitingFor
        )

        return Row(sessionId: sessionId, cwd: cwd, state: state, detail: waitingFor, pid: pid)
    }

    /// `status` — для интерактивных сессий, `state` — для фоновых.
    private static func mapState(status: String?, backgroundState: String?, waitingFor: String?) -> AgentState {
        if let backgroundState {
            switch backgroundState.lowercased() {
            case "working":  return .working
            case "blocked":  return .waitingPermission
            case "done":     return .done
            case "failed":   return .error
            case "stopped":  return .done
            default:         break
            }
        }

        switch status?.lowercased() {
        case "waiting":
            switch waitingFor?.lowercased() {
            case "permission prompt", "sandbox request", "worker request", "dialog open":
                return .waitingPermission
            case "input needed":
                return .waitingInput
            default:
                return .waitingInput
            }
        case "working", "running", "busy":
            return .working
        case "done", "idle", "completed":
            return .done
        case "error", "failed":
            return .error
        default:
            return .working
        }
    }
}
