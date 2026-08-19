import AppKit

/// Раскрывает панель ещё до того, как курсор с файлом дойдёт до окна.
///
/// Приём: на mouseDown запоминаем `changeCount` драг-пастборда, на mouseDragged
/// сравниваем. Если он изменился — тащат данные, а не просто водят мышью с
/// зажатой кнопкой. Отдельного системного события «начался драг» нет.
final class DragDetector {
    /// Зона, попадание в которую при активном драге считается «поднесли файл».
    var targetRect: NSRect = .zero
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?

    private var downMonitor: MouseMonitor?
    private var dragMonitor: MouseMonitor?
    private var upMonitor: MouseMonitor?

    private var changeCountAtDown = 0
    private var isDraggingData = false
    private var didEnter = false

    func start() {
        downMonitor = MouseMonitor(mask: [.leftMouseDown]) { [weak self] _ in
            self?.handleDown()
        }
        // Троттлинг 20 Гц — только на непрерывное перетаскивание.
        dragMonitor = MouseMonitor(mask: [.leftMouseDragged], throttle: 0.05) { [weak self] _ in
            self?.handleDragged()
        }
        // На отпускании троттлинга нет сознательно: пропустить его — значит
        // залипнуть в открытом состоянии.
        upMonitor = MouseMonitor(mask: [.leftMouseUp]) { [weak self] _ in
            self?.handleUp()
        }

        downMonitor?.start()
        dragMonitor?.start()
        upMonitor?.start()
    }

    func stop() {
        downMonitor?.stop()
        dragMonitor?.stop()
        upMonitor?.stop()
        downMonitor = nil
        dragMonitor = nil
        upMonitor = nil
    }

    private func handleDown() {
        changeCountAtDown = NSPasteboard(name: .drag).changeCount
        isDraggingData = false
        didEnter = false
    }

    private func handleDragged() {
        if !isDraggingData {
            let current = NSPasteboard(name: .drag).changeCount
            guard current != changeCountAtDown else { return }
            isDraggingData = true
        }

        guard !didEnter, targetRect.contains(NSEvent.mouseLocation) else { return }
        didEnter = true
        onEnter?()
    }

    private func handleUp() {
        if didEnter { onExit?() }
        isDraggingData = false
        didEnter = false
    }
}
