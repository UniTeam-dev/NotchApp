import SwiftUI

/// Состояние панели, которое видит SwiftUI. Размеры считает контроллер —
/// вью-модель их только хранит, чтобы вьюхи не лезли в NSScreen.
final class NotchViewModel: ObservableObject {
    @Published var isOpen = false
    @Published var tab: NotchTab = .music
    @Published var isDropTargeted = false
    /// Вместо вкладки показаны настройки.
    @Published var showsSettings = false

    /// Размер физического выреза. Всё, что нарисовано в этих границах,
    /// закрыто аппаратной челкой и пользователю не видно.
    @Published var closedSize = CGSize(width: 190, height: 32)
    /// Размер раскрытой панели.
    @Published var openSize = CGSize(width: 560, height: 214)

    /// Ширина «крыла» — полосы сбоку от выреза, в которой индикатор виден.
    let indicatorWing: CGFloat = 40

    /// Свёрнутая панель с крыльями: только в таком виде индикатор читается.
    var closedIndicatorSize: CGSize {
        CGSize(
            width: closedSize.width + indicatorWing * 2,
            height: closedSize.height
        )
    }

    var currentSize: CGSize { isOpen ? openSize : closedSize }
}
