import AppKit

/// Обёртка над глобальным и локальным мониторами событий мыши.
///
/// Разрешений не требует: TCC нужен только для событий клавиатуры и CGEventTap.
///
/// Троттлинг применяется **только** к непрерывным событиям движения. Если под
/// него попадёт отпускание кнопки (оно приходит через 8–16 мс после последнего
/// `.leftMouseDragged`), конец драга потеряется и панель залипнет открытой.
final class MouseMonitor {
    private let mask: NSEvent.EventTypeMask
    private let throttle: TimeInterval
    private let handler: (NSEvent) -> Void

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastFire: TimeInterval = 0

    private static let continuousTypes: Set<NSEvent.EventType> = [
        .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged
    ]

    init(mask: NSEvent.EventTypeMask, throttle: TimeInterval = 0, handler: @escaping (NSEvent) -> Void) {
        self.mask = mask
        self.throttle = throttle
        self.handler = handler
    }

    deinit {
        stop()
    }

    func start() {
        guard globalMonitor == nil, localMonitor == nil else { return }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.deliver(event)
        }
        // Локальный монитор нужен, чтобы события над собственной панелью
        // тоже доходили: глобальный их не отдаёт.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.deliver(event)
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func deliver(_ event: NSEvent) {
        if throttle > 0, MouseMonitor.continuousTypes.contains(event.type) {
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastFire >= throttle else { return }
            lastFire = now
        }
        handler(event)
    }
}
