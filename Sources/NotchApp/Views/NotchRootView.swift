import SwiftUI

struct NotchRootView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject var music: MusicModel
    @ObservedObject var shelf: ShelfStore
    @ObservedObject var agents: AgentStore

    var onRequestClose: () -> Void

    var body: some View {
        let size = viewModel.currentSize

        ZStack(alignment: .top) {
            // Аура лежит за пределами clipShape, поэтому мягко выходит за края.
            if let glow = agents.glow {
                NotchAura(glow: glow, isOpen: viewModel.isOpen, size: size)
            }
            panelBody(size: size)
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.85), value: viewModel.isOpen)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(alignment: .top) {
            dropCatcher(size: size)
        }
    }

    // MARK: - Приёмник файлов

    private func dropCatcher(size: CGSize) -> some View {
        let height = max(size.height, viewModel.openSize.height)
        return ShelfDropCatcher(
            onDrop: { pasteboard in
                let added = shelf.add(from: pasteboard)
                if added { viewModel.tab = .shelf }
                return added
            },
            onTargetingChanged: { targeted in
                viewModel.isDropTargeted = targeted
            }
        )
        .frame(width: size.width, height: height)
    }

    // MARK: - Тело панели

    private func panelBody(size: CGSize) -> some View {
        let topRadius: CGFloat = viewModel.isOpen ? 11 : 6
        let bottomRadius: CGFloat = viewModel.isOpen ? 24 : 12

        return ZStack(alignment: .top) {
            Color.black

            if viewModel.isOpen {
                expanded
                    .transition(.opacity)
            } else if let glow = agents.glow {
                ClosedIndicator(glow: glow, count: agents.attentionCount)
                    .frame(height: viewModel.closedSize.height)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(NotchShape(topRadius: topRadius, bottomRadius: bottomRadius))
        .overlay(alignment: .top) {
            dropHighlight(size: size)
        }
    }

    @ViewBuilder
    private func dropHighlight(size: CGSize) -> some View {
        if viewModel.isDropTargeted && viewModel.isOpen {
            NotchShape(topRadius: 11, bottomRadius: 24)
                .stroke(Color.accentColor.opacity(0.8), lineWidth: 2)
                .frame(width: size.width, height: size.height)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Раскрытая панель

    private var expanded: some View {
        VStack(spacing: 0) {
            // Не залезаем под саму челку.
            Spacer().frame(height: viewModel.closedSize.height)

            header
                .padding(.horizontal, 16)
                .padding(.top, 4)

            Divider()
                .overlay(Color.white.opacity(0.08))
                .padding(.horizontal, 14)
                .padding(.top, 6)

            content
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.bottom, 12)
        .frame(width: viewModel.openSize.width, height: viewModel.openSize.height, alignment: .top)
    }

    private var header: some View {
        HStack(spacing: 6) {
            ForEach(NotchTab.allCases) { tab in
                tabChip(for: tab)
            }
            Spacer(minLength: 8)
            IconButton(symbol: "xmark", help: "Закрыть", action: onRequestClose)
        }
    }

    private func tabChip(for tab: NotchTab) -> some View {
        let isAgents = tab == .agents
        let badge: Int = isAgents ? agents.attentionCount : 0
        let accent: Color? = isAgents ? agents.glow?.color : nil

        return TabChip(
            tab: tab,
            isSelected: viewModel.tab == tab,
            badge: badge,
            accent: accent,
            action: { viewModel.tab = tab }
        )
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.tab {
        case .music:
            MusicView(music: music)
        case .shelf:
            ShelfView(shelf: shelf, isDropTargeted: viewModel.isDropTargeted)
        case .agents:
            AgentsView(agents: agents)
        }
    }
}

// MARK: - Мелкие элементы

struct TabChip: View {
    let tab: NotchTab
    let isSelected: Bool
    let badge: Int
    /// Цвет текущего состояния агентов — тонкая рамка вокруг активной вкладки.
    var accent: Color? = nil
    let action: () -> Void

    private var badgeColor: Color {
        accent ?? Color(red: 1.0, green: 0.62, blue: 0.20)
    }

    private var borderColor: Color {
        guard isSelected, let accent else { return .clear }
        return accent.opacity(0.35)
    }

    private var background: Color {
        Color.white.opacity(isSelected ? 0.16 : 0.04)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 10, weight: .semibold))

                Text(tab.title)
                    .font(.system(size: 11, weight: .medium))

                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(badgeColor))
                        .foregroundStyle(Color.black)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(background))
            .overlay(Capsule().strokeBorder(borderColor, lineWidth: 1))
            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.6))
        }
        .buttonStyle(.plain)
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    var size: CGFloat = 11
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 24, height: 22)
                .background(Capsule().fill(Color.white.opacity(0.06)))
                .foregroundStyle(Color.white.opacity(0.75))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct EmptyHint: View {
    let symbol: String
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Color.white.opacity(0.35))

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.6))

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
