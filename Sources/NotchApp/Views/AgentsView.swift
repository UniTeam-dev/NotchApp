import SwiftUI

struct AgentsView: View {
    @ObservedObject var agents: AgentStore
    @State private var installError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            if agents.sessions.isEmpty {
                EmptyHint(
                    symbol: "sparkles",
                    title: "Никто не работает и не ждёт",
                    subtitle: hintText
                )
            } else {
                sessionList
            }

            footer
        }
    }

    private var sessionList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 4) {
                ForEach(agents.sessions) { session in
                    row(for: session)
                }
            }
        }
    }

    /// Убрать можно любую строку, не только завершённую: сессия, про которую
    /// хук соврал или чьё приложение закрыли молча, иначе застревает навсегда.
    private func row(for session: AgentSession) -> AgentRow {
        AgentRow(
            session: session,
            onActivate: { agents.activate(session) },
            onDismiss: { agents.dismiss(session) }
        )
    }

    private var hintText: String {
        if !agents.hooksInstalled.claude || !agents.hooksInstalled.cursor {
            return "Поставьте хуки — тогда Claude Code и Cursor начнут сообщать о своём состоянии"
        }
        return "Здесь те сессии, что работают, ждут вас или закончили и ждут, когда вы к ним зайдёте"
    }

    // MARK: - Шапка

    private var header: some View {
        HStack(spacing: 8) {
            Text("Агенты")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.6))

            if agents.attentionCount > 0 {
                badge(
                    text: "\(agents.attentionCount) ждут вас",
                    color: agents.glow?.color ?? AgentState.waitingPermission.color
                )
            }

            if agents.awaitingVisitCount > 0 {
                badge(
                    text: "\(agents.awaitingVisitCount) готовы",
                    color: AgentState.done.color
                )
            }

            Spacer()

            hookBadge(source: .claude, installed: agents.hooksInstalled.claude)
            hookBadge(source: .cursor, installed: agents.hooksInstalled.cursor)

            if !agents.hooksInstalled.claude || !agents.hooksInstalled.cursor {
                installButton
            }
        }
    }

    private func badge(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .background(Capsule().fill(color))
            .foregroundStyle(Color.black)
    }

    private var installButton: some View {
        Button(action: install) {
            Text("Поставить хуки")
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.accentColor.opacity(0.85)))
                .foregroundStyle(Color.white)
        }
        .buttonStyle(.plain)
    }

    private func hookBadge(source: AgentSource, installed: Bool) -> some View {
        let opacity: Double = installed ? 0.5 : 0.28
        let markOpacity: Double = installed ? 0.75 : 0.4

        return HStack(spacing: 3) {
            Image(systemName: source.mark)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(source.tint.opacity(markOpacity))

            Image(systemName: installed ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 8))

            Text(source.title)
                .font(.system(size: 8, weight: .medium))
        }
        .foregroundStyle(Color.white.opacity(opacity))
        .help(installed ? "Хуки \(source.title) установлены" : "Хуки \(source.title) не установлены")
    }

    // MARK: - Подвал

    @ViewBuilder
    private var footer: some View {
        if let installError {
            Text(installError)
                .font(.system(size: 9))
                .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.42))
                .lineLimit(2)
        } else if agents.awaitingVisitCount > 0 {
            HStack(spacing: 6) {
                Text("Готовые остаются здесь, пока в них не зайдёшь")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.white.opacity(0.35))

                Spacer()

                Button(action: agents.dismissDone) {
                    Text("убрать все")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help("Убрать завершённые сессии, не переходя в них")
            }
        } else if !AX.isTrusted {
            Text("Выдайте Accessibility — без него клик поднимает приложение, но не открывает нужный чат")
                .font(.system(size: 9))
                .foregroundStyle(Color.white.opacity(0.35))
                .lineLimit(2)
        }
    }

    private func install() {
        do {
            try HookInstaller.installAll()
            installError = nil
            agents.refreshHookStatus()
        } catch {
            installError = error.localizedDescription
        }
    }
}

// MARK: - Строка сессии

struct AgentRow: View {
    let session: AgentSession
    let onActivate: () -> Void
    /// Есть только у завершённых: убрать строку, не переходя в чат.
    var onDismiss: (() -> Void)?

    @State private var isHovering = false

    private var stateColor: Color { session.state.color }

    /// Подсвечиваем и «ждёт», и «готово, но не заходили»: и то и другое — долг
    /// перед человеком, просто разной срочности.
    private var isPending: Bool { session.requiresAttention || session.awaitsVisit }

    private var rowBackground: some View {
        let base = Color.white.opacity(isHovering ? 0.08 : 0.04)
        return RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(base)
            .overlay { attentionWash }
    }

    @ViewBuilder
    private var attentionWash: some View {
        if isPending {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [stateColor.opacity(session.requiresAttention ? 0.22 : 0.14), Color.clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
    }

    var body: some View {
        Button(action: onActivate) {
            HStack(spacing: 9) {
                sourceMark
                titles
                Spacer(minLength: 6)
                trailing
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(rowBackground)
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        isPending ? stateColor.opacity(session.requiresAttention ? 0.35 : 0.25) : Color.clear,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    /// Иконка IDE в кружке цвета состояния плюс гало у тех, кто ждёт.
    private var sourceMark: some View {
        ZStack {
            Circle()
                .fill(stateColor.opacity(0.18))
                .frame(width: 24, height: 24)

            if isPending {
                Circle()
                    .stroke(stateColor.opacity(0.5), lineWidth: 1)
                    .frame(width: 24, height: 24)
                    .shadow(color: stateColor.opacity(0.7), radius: 6)
            }

            Image(systemName: session.source.mark)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(session.source.tint)
        }
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(session.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.9))
                .lineLimit(1)

            Text(subtitleText)
                .font(.system(size: 9))
                .foregroundStyle(Color.white.opacity(0.45))
                .lineLimit(1)
        }
    }

    private var subtitleText: String {
        var parts = [session.state.title]

        if session.awaitsVisit {
            parts.append(session.hasEnded ? "чат закрыт, вы не заходили" : "вы ещё не заходили")
        } else if let detail = session.detail, !detail.isEmpty {
            parts.append(detail)
        }

        if let worktree = session.worktreeName {
            parts.append(worktree)
        }

        return parts.joined(separator: " · ")
    }

    private var trailing: some View {
        HStack(spacing: 7) {
            if let onDismiss, isHovering {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help("Убрать из списка, не переходя в чат")
            }

            PulsingDot(color: stateColor, animated: session.requiresAttention)
                .frame(width: 7, height: 7)
                .shadow(color: stateColor.opacity(isPending ? 0.8 : 0), radius: 4)

            Image(systemName: "arrow.up.forward")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.5))
                .opacity(isHovering ? 1 : 0)
        }
    }
}
