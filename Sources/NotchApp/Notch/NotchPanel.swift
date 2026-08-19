import AppKit

/// Окно панели.
///
/// Ключевые решения:
/// - уровень `.mainMenu + 3`, чтобы лежать выше меню-бара;
/// - `.nonactivatingPanel` — клик по панели не уводит фокус с рабочего приложения;
/// - `collectionBehavior` со `.stationary` и `.fullScreenAuxiliary`, чтобы панель
///   жила на всех Spaces и не участвовала в переключении окон.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false
        hidesOnDeactivate = false

        // Пока панель закрыта — сквозная для мыши. Это не оптимизация:
        // высокоуровневое окно, перехватывающее мышь в зоне автовыезда меню-бара,
        // залипает в полноэкранном режиме.
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = false
    }

    // Панель не должна становиться key: иначе она забирает фокус у редактора.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
