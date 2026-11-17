import Foundation
import IOKit.pwr_mgt

/// «Не уходить в сон»: пока включено, не гаснет экран и не засыпает система.
///
/// То же, что `caffeinate -di`, но без дочернего процесса. Голый `caffeinate`
/// держит только систему — экран при нём всё равно гаснет. Ассерты живут
/// не дольше процесса: после выхода из NotchApp Mac снова засыпает сам.
/// Сон по закрытой крышке ассертами не отменить.
final class KeepAwake: ObservableObject {
    @Published private(set) var isOn = false
    private var assertions: [IOPMAssertionID] = []

    func toggle() {
        isOn ? release() : hold()
    }

    private func hold() {
        let types = [kIOPMAssertionTypePreventUserIdleDisplaySleep, kIOPMAssertionTypePreventUserIdleSystemSleep]
        for type in types {
            var id = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                type as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "NotchApp: не уходить в сон" as CFString,
                &id
            )
            if result == kIOReturnSuccess { assertions.append(id) }
        }
        isOn = !assertions.isEmpty
    }

    private func release() {
        assertions.forEach { IOPMAssertionRelease($0) }
        assertions.removeAll()
        isOn = false
    }
}
