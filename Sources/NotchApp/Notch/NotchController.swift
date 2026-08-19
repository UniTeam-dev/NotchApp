import AppKit
import SwiftUI

/// Управляет панелью: геометрия, ховер, drag-to-open, показ и скрытие.
///
/// Свойство окна намеренно называется `notchPanel`, а не `panel`: у `NSObject`
/// из AppKit есть устаревший метод `panel(_:isValidFilename:)`, и обычное имя
/// `panel` даёт неоднозначность при разрешении имён.
final class NotchController: NSObject {
    let viewModel = NotchViewModel()

    private var notchPanel: NotchPanel?
    private var hostingView: NotchHostingView<NotchRootView>?
    private var currentScreen: NSScreen?

    private var moveMonitor: MouseMonitor?
    private var clickMonitor: MouseMonitor?
    private let dragDetector = DragDetector()

    private var openWorkItem: DispatchWorkItem?
    private var closeWorkItem: DispatchWorkItem?

    /// Сколько курсор должен продержаться в челке, прежде чем панель поедет вниз.
    private let hoverOpenDelay: TimeInterval = 0.12
    /// Гистерезис на выходе: без него панель схлопывается при проходе курсора
    /// по диагонали через верхний край.
    private let hoverCloseDelay: TimeInterval = 0.28

    /// Запас вокруг контента, в который вытекает свечение ауры.
    /// Сверху запаса нет: контент прижат к кромке экрана.
    private let bleed: CGFloat = 46

    private let music: MusicModel
    private let shelf: ShelfStore
    private let agents: AgentStore

    init(music: MusicModel, shelf: ShelfStore, agents: AgentStore) {
        self.music = music
        self.shelf = shelf
        self.agents = agents
        super.init()
    }

    // MARK: - Жизненный цикл

    func start() {
        currentScreen = targetScreen()
        rebuildPanel()

        moveMonitor = MouseMonitor(mask: [.mouseMoved], throttle: 0.05) { [weak self] _ in
            self?.handleMouseMoved()
        }
        moveMonitor?.start()

        clickMonitor = MouseMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.handleClick()
        }
        clickMonitor?.start()

        dragDetector.onEnter = { [weak self] in
            guard let self else { return }
            self.viewModel.tab = .shelf
            self.open()
        }
        dragDetector.start()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(spaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    func stop() {
        moveMonitor?.stop()
        clickMonitor?.stop()
        dragDetector.stop()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func screenParametersChanged() {
        currentScreen = targetScreen()
        rebuildPanel()
    }

    @objc private func spaceChanged() {
        // При переключении Space панель может «потеряться» — просто поднимаем её снова.
        notchPanel?.orderFrontRegardless()
    }

    // MARK: - Геометрия

    private func targetScreen() -> NSScreen {
        if let screen = NSScreen.screen(containing: NSEvent.mouseLocation), screen.hasNotch {
            return screen
        }
        if let notched = NSScreen.notched { return notched }
        if let screen = NSScreen.screen(containing: NSEvent.mouseLocation) { return screen }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    private func geometry(for screen: NSScreen) -> (panelFrame: NSRect, closed: CGSize, open: CGSize) {
        let anchor = screen.anchorRect

        let widthLimit = screen.frame.width - 24
        let openWidth = min(max(anchor.width + 380, 560), widthLimit)
        let openHeight = anchor.height + 182

        // Прижимаемся к frame.maxY, а не к visibleFrame: последний уже вычел меню-бар.
        let originX = anchor.midX - openWidth / 2 - bleed
        let originY = screen.frame.maxY - openHeight - bleed
        let frame = NSRect(
            x: originX,
            y: originY,
            width: openWidth + bleed * 2,
            height: openHeight + bleed
        )

        return (frame, anchor.size, CGSize(width: openWidth, height: openHeight))
    }

    /// Зона, при наведении на которую панель раскрывается.
    private func hotRect(for screen: NSScreen) -> NSRect {
        let anchor = screen.anchorRect
        return NSRect(
            x: anchor.minX - 46,
            y: anchor.minY,
            width: anchor.width + 92,
            height: anchor.height
        )
    }

    /// Зона для перетаскивания — заметно больше, чтобы файл можно было «поднести».
    private func dragRect(for screen: NSScreen) -> NSRect {
        let anchor = screen.anchorRect
        return NSRect(
            x: anchor.minX - 130,
            y: anchor.minY - 26,
            width: anchor.width + 260,
            height: anchor.height + 26
        )
    }

    /// Интерактивная область в координатах contentView: только само тело панели,
    /// без запаса под свечение.
    private func currentInteractiveRect() -> NSRect? {
        guard viewModel.isOpen, let panel = notchPanel else { return nil }
        let content = panel.frame.size
        let size = viewModel.currentSize
        return NSRect(
            x: (content.width - size.width) / 2,
            y: content.height - size.height,
            width: size.width,
            height: size.height
        )
    }

    // MARK: - Окно

    private func rebuildPanel() {
        let screen = currentScreen ?? targetScreen()
        let geo = geometry(for: screen)

        viewModel.closedSize = geo.closed
        viewModel.openSize = geo.open
        dragDetector.targetRect = dragRect(for: screen)

        if let existing = notchPanel {
            existing.setFrame(geo.panelFrame, display: true)
            existing.orderFrontRegardless()
            return
        }

        let panel = NotchPanel(contentRect: geo.panelFrame)
        let root = NotchRootView(
            viewModel: viewModel,
            music: music,
            shelf: shelf,
            agents: agents,
            onRequestClose: { [weak self] in self?.close() }
        )

        let hosting = NotchHostingView(rootView: root)
        hosting.interactiveRect = { [weak self] in self?.currentInteractiveRect() }
        hosting.frame = NSRect(origin: .zero, size: geo.panelFrame.size)
        hosting.autoresizingMask = [.width, .height]

        panel.contentView = hosting
        panel.orderFrontRegardless()

        notchPanel = panel
        hostingView = hosting
    }

    private func rebuildPanelFrameIfNeeded() {
        guard let panel = notchPanel, let screen = currentScreen else { return }
        let geo = geometry(for: screen)
        if panel.frame != geo.panelFrame {
            panel.setFrame(geo.panelFrame, display: true)
            viewModel.closedSize = geo.closed
            viewModel.openSize = geo.open
        }
    }

    // MARK: - Реакция на мышь

    private func handleMouseMoved() {
        guard let panel = notchPanel else { return }
        let location = NSEvent.mouseLocation

        if viewModel.isOpen {
            if panel.frame.insetBy(dx: -14, dy: -14).contains(location) {
                cancelClose()
            } else {
                scheduleClose()
            }
            return
        }

        // Закрытое состояние: следим за экраном под курсором.
        let screen = NSScreen.screen(containing: location) ?? targetScreen()
        if screen !== currentScreen, screen.hasNotch || NSScreen.notched == nil {
            currentScreen = screen
            rebuildPanel()
        }

        if hotRect(for: currentScreen ?? screen).contains(location) {
            scheduleOpen()
        } else {
            cancelOpen()
        }
    }

    private func handleClick() {
        guard viewModel.isOpen, let panel = notchPanel else { return }
        if !panel.frame.contains(NSEvent.mouseLocation) {
            close()
        }
    }

    // MARK: - Открытие и закрытие

    private func scheduleOpen() {
        guard openWorkItem == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            self?.openWorkItem = nil
            self?.open()
        }
        openWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + hoverOpenDelay, execute: item)
    }

    private func cancelOpen() {
        openWorkItem?.cancel()
        openWorkItem = nil
    }

    private func scheduleClose() {
        guard closeWorkItem == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            self?.closeWorkItem = nil
            self?.close()
        }
        closeWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + hoverCloseDelay, execute: item)
    }

    private func cancelClose() {
        closeWorkItem?.cancel()
        closeWorkItem = nil
    }

    func open() {
        cancelOpen()
        cancelClose()
        guard !viewModel.isOpen else { return }

        rebuildPanelFrameIfNeeded()
        notchPanel?.ignoresMouseEvents = false
        notchPanel?.acceptsMouseMovedEvents = true
        notchPanel?.orderFrontRegardless()

        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            viewModel.isOpen = true
        }
    }

    func close() {
        cancelOpen()
        cancelClose()
        guard viewModel.isOpen else { return }

        withAnimation(.spring(response: 0.30, dampingFraction: 0.88)) {
            viewModel.isOpen = false
        }
        viewModel.isDropTargeted = false

        // Возвращаем сквозную для мыши только после того, как схлопывание доиграло.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) { [weak self] in
            guard let self, !self.viewModel.isOpen else { return }
            self.notchPanel?.ignoresMouseEvents = true
            self.notchPanel?.acceptsMouseMovedEvents = false
        }
    }

    /// Открыть панель на конкретной вкладке (из меню-бара).
    func open(tab: NotchTab) {
        viewModel.tab = tab
        open()
    }
}
