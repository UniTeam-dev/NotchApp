import AppKit
import SwiftUI

/// Приёмник файлов на всю площадь панели.
///
/// Тонкость: `hitTest` возвращает nil, поэтому вью не перехватывает клики и не
/// мешает кнопкам SwiftUI. Целью драга он при этом остаётся — адресация драга
/// идёт по зарегистрированным типам, а не через hitTest.
struct ShelfDropCatcher: NSViewRepresentable {
    var onDrop: (NSPasteboard) -> Bool
    var onTargetingChanged: (Bool) -> Void

    func makeNSView(context: Context) -> DropCatcherView {
        let view = DropCatcherView(frame: .zero)
        view.onDrop = onDrop
        view.onTargetingChanged = onTargetingChanged
        view.registerTypes()
        return view
    }

    func updateNSView(_ nsView: DropCatcherView, context: Context) {
        nsView.onDrop = onDrop
        nsView.onTargetingChanged = onTargetingChanged
    }
}

final class DropCatcherView: NSView {
    var onDrop: ((NSPasteboard) -> Bool)?
    var onTargetingChanged: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        subscribeToReregistrationEvents()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) не поддерживается")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    /// Клики нас не касаются — мы только цель драга.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func registerTypes() {
        registerForDraggedTypes([.fileURL, .URL, .string])
    }

    /// Регистрация типов теряется при переключении Spaces и после разблокировки
    /// экрана. Системного сигнала «регистрация слетела» нет, поэтому просто
    /// переустанавливаем её по смежным уведомлениям, с запасом по времени.
    private func subscribeToReregistrationEvents() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(
            self,
            selector: #selector(scheduleReregistration),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(scheduleReregistration),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(scheduleReregistration),
            name: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )
    }

    @objc private func scheduleReregistration() {
        for delay in [0.1, 0.6, 1.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.registerTypes()
            }
        }
    }

    // MARK: - Драг

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onTargetingChanged?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onTargetingChanged?(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        onTargetingChanged?(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { onTargetingChanged?(false) }
        return onDrop?(sender.draggingPasteboard) ?? false
    }
}
