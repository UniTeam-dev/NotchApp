import SwiftUI

/// Состояние панели, которое видит SwiftUI. Размеры считает контроллер —
/// вью-модель их только хранит, чтобы вьюхи не лезли в NSScreen.
final class NotchViewModel: ObservableObject {
    @Published var isOpen = false
    @Published var tab: NotchTab = .music
    @Published var isDropTargeted = false

    /// Размер свёрнутого состояния — ровно физическая челка (или её эрзац).
    @Published var closedSize = CGSize(width: 190, height: 32)
    /// Размер раскрытой панели.
    @Published var openSize = CGSize(width: 560, height: 214)

    var currentSize: CGSize { isOpen ? openSize : closedSize }
}
