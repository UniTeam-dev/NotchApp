import Foundation
import Combine

/// Состояние всех известных сессий.
///
/// Два источника: хуки (мгновенно) и опрос `claude agents --json` (полно).
/// При расхождении приоритет у хука моложе двух секунд.
final class AgentStore: ObservableObject {
    @Published var sessions: [AgentSession] = []
    @Published var hooksInstalled = HookStatus()

    var attentionCount: Int { sessions.filter(\.requiresAttention).count }

    private let inbox = AgentInbox()
    private var pollTimer: Timer?

    /// У Cursor нет события «жду подтверждения». Суррогат —
    /// `beforeShellExecution` / `beforeMCPExecution`, но при auto-run они летят на
    /// каждую команду. Поэтому статус выставляется только если за 6 секунд по этой
    /// сессии не пришло ни `after*`-события, ни любого другого.
    private var cursorPending: [String: DispatchWorkItem] = [:]
    private let cursorDebounce: TimeInterval = 6

    /// Сколько держим завершённые сессии, прежде чем убрать из списка.
    private let doneLifetime: TimeInterval = 90

    // MARK: - Жизненный цикл

    func start() {
        refreshHookStatus()

        inbox.onEvent = { [weak self] event in
            self?.apply(event)
        }
        inbox.start()

        poll()
        let timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stop() {
        inbox.stop()
        pollTimer?.invalidate()
        pollTimer = nil
        cursorPending.values.forEach { $0.cancel() }
        cursorPending.removeAll()
    }

    func refreshHookStatus() {
        hooksInstalled = HookInstaller.status()
    }

    // MARK: - Хуки

    private func apply(_ event: HookEvent) {
        switch event.source {
        case .claude: applyClaude(event)
        case .cursor: applyCursor(event)
        case .cloud:  break
        }
    }

    private func applyClaude(_ event: HookEvent) {
        let id = AgentSession.makeID(source: .claude, sessionId: event.sessionId)

        switch event.event {
        case "SessionEnd":
            remove(id: id)
            return
        case "Stop":
            update(event, state: .done)
        case "StopFailure":
            update(event, state: .error)
        case "PermissionRequest":
            update(event, state: .waitingPermission)
        case "Notification":
            switch event.notificationType {
            case "permission_prompt":
                update(event, state: .waitingPermission)
            case "idle_prompt", "agent_needs_input":
                update(event, state: .waitingInput)
            case "agent_completed":
                update(event, state: .done)
            default:
                update(event, state: .waitingInput)
            }
        case "SessionStart", "UserPromptSubmit", "PreToolUse",
             "PostToolUse", "PostToolUseFailure", "PermissionDenied":
            update(event, state: .working)
        default:
            update(event, state: .working)
        }
    }

    private func applyCursor(_ event: HookEvent) {
        let id = AgentSession.makeID(source: .cursor, sessionId: event.sessionId)

        // Любое событие снимает отложенное «ждёт подтверждения».
        cursorPending[id]?.cancel()
        cursorPending[id] = nil

        switch event.event {
        case "beforeShellExecution", "beforeMCPExecution":
            update(event, state: .working)
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.cursorPending[id] = nil
                self.setState(id: id, state: .waitingPermission)
            }
            cursorPending[id] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + cursorDebounce, execute: work)
        case "stop", "afterAgentTurn", "agentTurnEnd":
            update(event, state: .done)
        default:
            update(event, state: .working)
        }
    }

    // MARK: - Опрос

    private func poll() {
        guard ClaudeAgentsProbe.isAvailable else {
            pruneStale()
            return
        }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let rows = ClaudeAgentsProbe.poll()
            DispatchQueue.main.async {
                self?.merge(rows)
            }
        }
    }

    private func merge(_ rows: [ClaudeAgentsProbe.Row]) {
        var updated = sessions
        let now = Date()
        var seen = Set<String>()

        for row in rows {
            let id = AgentSession.makeID(source: .claude, sessionId: row.sessionId)
            seen.insert(id)

            if let index = updated.firstIndex(where: { $0.id == id }) {
                // Свежий хук важнее опроса: он приходит раньше и точнее.
                let hookAt = updated[index].lastHookAt
                let hookIsFresh = hookAt.map { now.timeIntervalSince($0) < 2 } ?? false
                if !hookIsFresh {
                    updated[index].state = row.state
                    updated[index].detail = row.detail
                }
                if !row.cwd.isEmpty { updated[index].cwd = row.cwd }
                updated[index].pid = row.pid ?? updated[index].pid
                updated[index].updatedAt = now
            } else {
                updated.append(
                    AgentSession(
                        id: id,
                        sessionId: row.sessionId,
                        source: .claude,
                        state: row.state,
                        cwd: row.cwd,
                        detail: row.detail,
                        pid: row.pid,
                        updatedAt: now,
                        lastHookAt: nil
                    )
                )
            }
        }

        // Сессии Claude Code, которых опрос больше не видит, считаем закрытыми.
        updated.removeAll { session in
            session.source == .claude
                && !seen.contains(session.id)
                && now.timeIntervalSince(session.updatedAt) > 10
        }

        sessions = sorted(prune(updated, now: now))
    }

    // MARK: - Изменение списка

    private func update(_ event: HookEvent, state: AgentState) {
        let id = AgentSession.makeID(source: event.source, sessionId: event.sessionId)
        let now = Date()
        var updated = sessions

        if let index = updated.firstIndex(where: { $0.id == id }) {
            updated[index].state = state
            updated[index].updatedAt = now
            updated[index].lastHookAt = now
            if !event.cwd.isEmpty { updated[index].cwd = event.cwd }
            if let pid = event.pid { updated[index].pid = pid }
            updated[index].detail = event.toolName
        } else {
            updated.append(
                AgentSession(
                    id: id,
                    sessionId: event.sessionId,
                    source: event.source,
                    state: state,
                    cwd: event.cwd,
                    detail: event.toolName,
                    pid: event.pid,
                    updatedAt: now,
                    lastHookAt: now
                )
            )
        }

        sessions = sorted(prune(updated, now: now))
    }

    private func setState(id: String, state: AgentState) {
        var updated = sessions
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        updated[index].state = state
        updated[index].updatedAt = Date()
        sessions = sorted(updated)
    }

    private func remove(id: String) {
        sessions = sessions.filter { $0.id != id }
    }

    private func pruneStale() {
        let now = Date()
        let cleaned = prune(sessions, now: now)
        if cleaned.count != sessions.count {
            sessions = sorted(cleaned)
        }
    }

    private func prune(_ list: [AgentSession], now: Date) -> [AgentSession] {
        list.filter { session in
            guard session.state == .done else { return true }
            return now.timeIntervalSince(session.updatedAt) < doneLifetime
        }
    }

    /// Требующие внимания — сверху. От этого порядка зависит выбор цвета ауры.
    private func sorted(_ list: [AgentSession]) -> [AgentSession] {
        list.sorted { lhs, rhs in
            if lhs.state.priority != rhs.state.priority {
                return lhs.state.priority < rhs.state.priority
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    // MARK: - Переход к сессии

    func activate(_ session: AgentSession) {
        SessionActivator.activate(session)
    }
}
