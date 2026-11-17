import Foundation
import Combine

/// Состояние всех известных сессий.
///
/// Два источника: хуки (мгновенно) и опрос `claude agents --json` (полно).
/// При расхождении приоритет у хука моложе двух секунд.
///
/// Отдельное правило для «готово»: такая сессия не исчезает по таймеру, а ждёт,
/// пока в неё перейдут. Момент «агент закончил» — ровно тот, ради которого
/// смотрят на челку, и терять его из-за того, что человек отошёл, нельзя.
final class AgentStore: ObservableObject {
    @Published var sessions: [AgentSession] = []
    @Published var hooksInstalled = HookStatus()

    /// Сессии, которые спрашивают человека прямо сейчас.
    var attentionCount: Int { sessions.filter { $0.requiresAttention }.count }
    /// Завершённые сессии, в которые ещё не заходили.
    var awaitingVisitCount: Int { sessions.filter { $0.awaitsVisit }.count }
    /// Всё, что ждёт человека, — это число видно в закрытой челке.
    var pendingCount: Int { attentionCount + awaitingVisitCount }

    private let inbox = AgentInbox()
    private var pollTimer: Timer?

    /// У Cursor нет события «жду подтверждения». Суррогат —
    /// `beforeShellExecution` / `beforeMCPExecution`, но при auto-run они летят на
    /// каждую команду. Поэтому статус выставляется только если за 6 секунд по этой
    /// сессии не пришло ни `after*`-события, ни любого другого.
    private var cursorPending: [String: DispatchWorkItem] = [:]
    private let cursorDebounce: TimeInterval = 6

    /// Сессия «работает», от которой два часа нет ни одного события, — это
    /// почти наверняка след от закрытого без `SessionEnd` приложения.
    private let workingLifetime: TimeInterval = 2 * 3600
    /// То же для «ждёт» и «ошибки»: спустя шесть часов это уже не ожидание,
    /// а мусор, который некому убрать. «Готово» под это правило не попадает —
    /// оно держится до перехода, в этом весь смысл.
    private let staleLifetime: TimeInterval = 6 * 3600

    /// Сессии, по которым переход уже совершён или строку убрали руками.
    ///
    /// Без этого список воскресает: опрос идёт раз в три секунды, живую, но
    /// простаивающую сессию `claude agents` отдаёт как `idle`, и она тут же
    /// возвращается в список зелёной строкой. Плюс `idle_prompt` от Claude Code
    /// прилетает через минуту после конца работы — уже по закрытой сессии.
    private var suppressed: [String: Date] = [:]
    private let suppressionLifetime: TimeInterval = 6 * 3600

    /// Ключи последнего сохранения — чтобы не писать файл на каждый хук.
    private var persistedKeys: [String] = []

    // MARK: - Жизненный цикл

    func start() {
        refreshHookStatus()

        // Непросмотренные «готово» с прошлого запуска.
        let restored = AgentArchive.load()
        if !restored.isEmpty { commit(restored) }

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
            finish(id: id)
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
                // `idle_prompt` прилетает через минуту после завершения работы.
                // Для непросмотренного «готово» это не новый вопрос, а тишина:
                // если поднять его в «ждёт ответа», законченный чат начнёт
                // биться тревожным цветом на ровном месте.
                update(event, state: currentState(of: id) == .done ? .done : .waitingInput)
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
        case "beforeSubmitPrompt", "beforeReadFile", "afterFileEdit",
             "preToolUse", "PreToolUse", "postToolUse", "PostToolUse",
             "SessionStart", "sessionStart", "UserPromptSubmit":
            // Признаки живой работы, не требующие подтверждения.
            // camelCase / PascalCase — Cursor дублирует Claude-хуки с теми же именами.
            update(event, state: .working)

        case "beforeShellExecution", "beforeMCPExecution":
            update(event, state: .working)
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.cursorPending[id] = nil
                self.setState(id: id, state: .waitingPermission)
            }
            cursorPending[id] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + cursorDebounce, execute: work)
        case "stop", "Stop", "afterAgentTurn", "agentTurnEnd":
            update(event, state: .done)
        case "SessionEnd", "sessionEnd":
            finish(id: id)
        default:
            update(event, state: .working)
        }
    }

    // MARK: - Опрос

    private func poll() {
        // Целиком в фон: проверка доступности сама по себе может спросить
        // логин-шелл, а это секунды. На главном потоке это был бы фриз панели.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard ClaudeAgentsProbe.isAvailable else {
                DispatchQueue.main.async { self?.pruneStale() }
                return
            }
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

            // По сессии уже сходили. Возвращать её в список только потому, что
            // CLI всё ещё считает её живой, нельзя — иначе кнопка «убрать»
            // выглядит сломанной. Настоящая работа снимает подавление.
            if isSuppressed(id, now: now) {
                if row.state == .working {
                    suppressed[id] = nil
                } else {
                    continue
                }
            }

            seen.insert(id)

            if let index = updated.firstIndex(where: { $0.id == id }) {
                // Свежий хук важнее опроса: он приходит раньше и точнее.
                let hookAt = updated[index].lastHookAt
                let hookIsFresh = hookAt.map { now.timeIntervalSince($0) < 2 } ?? false
                // И отдельно: опрос не имеет права понизить непросмотренное
                // «готово» обратно в «работает» — так теряется весь сигнал.
                let wouldLoseDone = updated[index].awaitsVisit && row.state == .working

                if !hookIsFresh, !wouldLoseDone {
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
        // Кроме непросмотренных «готово»: они держатся до перехода, даже когда
        // сама сессия давно закрыта.
        updated.removeAll { session in
            session.source == .claude
                && !seen.contains(session.id)
                && !session.awaitsVisit
                && now.timeIntervalSince(session.updatedAt) > 10
        }

        commit(prune(updated, now: now))
    }

    // MARK: - Изменение списка

    private func currentState(of id: String) -> AgentState? {
        sessions.first(where: { $0.id == id })?.state
    }

    private func isSuppressed(_ id: String, now: Date) -> Bool {
        guard let since = suppressed[id] else { return false }
        guard now.timeIntervalSince(since) < suppressionLifetime else {
            suppressed[id] = nil
            return false
        }
        return true
    }

    private func update(_ event: HookEvent, state: AgentState) {
        let id = AgentSession.makeID(source: event.source, sessionId: event.sessionId)
        let now = Date()

        // Хвост событий по закрытой или уже отсмотренной сессии не должен
        // воскрешать строку. Признак настоящей новой работы — «работает».
        if isSuppressed(id, now: now) {
            guard state == .working else { return }
            suppressed[id] = nil
        }

        var updated = sessions

        if let index = updated.firstIndex(where: { $0.id == id }) {
            let wasVisited = updated[index].visitedAt != nil
            updated[index].state = state
            updated[index].updatedAt = now
            updated[index].lastHookAt = now
            if !event.cwd.isEmpty { updated[index].cwd = event.cwd }
            if let pid = event.pid { updated[index].pid = pid }
            if let transcript = event.transcriptPath { updated[index].transcriptPath = transcript }
            updated[index].detail = event.toolName
            // Событие после визита — это уже новая работа, и её результат
            // придётся отсматривать заново.
            if wasVisited {
                updated[index].visitedAt = nil
                updated[index].hasEnded = false
            }
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
                    lastHookAt: now,
                    transcriptPath: event.transcriptPath
                )
            )
        }

        commit(prune(updated, now: now))
    }

    private func setState(id: String, state: AgentState) {
        var updated = sessions
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        updated[index].state = state
        updated[index].updatedAt = Date()
        commit(updated)
    }

    /// Сессия закрылась. Непросмотренное «готово» переживает закрытие: строка
    /// остаётся, просто помечается завершённой.
    private func finish(id: String) {
        var updated = sessions
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }

        if updated[index].awaitsVisit {
            updated[index].hasEnded = true
        } else {
            updated.remove(at: index)
            suppressed[id] = Date()
        }
        commit(updated)
    }

    private func pruneStale() {
        let now = Date()
        let cleaned = prune(sessions, now: now)
        if cleaned.count != sessions.count {
            commit(cleaned)
        }
    }

    private func prune(_ list: [AgentSession], now: Date) -> [AgentSession] {
        list.filter { session in
            switch session.state {
            case .done:
                // Держим до перехода. После перехода строка убирается сразу
                // в `activate`, так что сюда такие уже не доходят.
                return session.visitedAt == nil
            case .working:
                return now.timeIntervalSince(session.updatedAt) < workingLifetime
            default:
                return now.timeIntervalSince(session.updatedAt) < staleLifetime
            }
        }
    }

    /// Единственная точка записи в `sessions`: сортирует и сохраняет то,
    /// что должно пережить перезапуск.
    private func commit(_ list: [AgentSession]) {
        sessions = sorted(list)

        let pending = sessions.filter { $0.awaitsVisit }
        let keys = pending.map { "\($0.id)|\($0.hasEnded)|\($0.updatedAt.timeIntervalSince1970)" }
        guard keys != persistedKeys else { return }
        persistedKeys = keys
        AgentArchive.save(pending)
    }

    /// Требующие внимания — сверху. От этого порядка зависит выбор цвета ауры,
    /// поэтому у сортировки есть третий ключ: без него сессии с одинаковым
    /// временем меняются местами на каждом опросе, и аура моргает.
    private func sorted(_ list: [AgentSession]) -> [AgentSession] {
        list.sorted { lhs, rhs in
            if lhs.state.priority != rhs.state.priority {
                return lhs.state.priority < rhs.state.priority
            }
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.id < rhs.id
        }
    }

    // MARK: - Переход к сессии

    func activate(_ session: AgentSession) {
        SessionActivator.activate(session)

        // Переход совершён — «готово» больше не держим.
        var updated = sessions
        guard let index = updated.firstIndex(where: { $0.id == session.id }) else { return }
        updated[index].visitedAt = Date()
        if updated[index].state == .done {
            updated.remove(at: index)
            suppressed[session.id] = Date()
        }
        commit(updated)
    }

    /// Убрать строку, не переходя в сессию: ✕ на строке.
    func dismiss(_ session: AgentSession) {
        suppressed[session.id] = Date()
        commit(sessions.filter { $0.id != session.id })
    }

    /// Убрать все завершённые разом — из меню статус-бара.
    func dismissDone() {
        let now = Date()
        for session in sessions where session.state == .done {
            suppressed[session.id] = now
        }
        commit(sessions.filter { $0.state != .done })
    }
}
