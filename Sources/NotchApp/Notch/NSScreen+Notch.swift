import AppKit

extension NSScreen {
    /// Экран, внутри которого лежит точка (в глобальных координатах).
    static func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }

    /// Первый экран с физической челкой, если такой есть.
    static var notched: NSScreen? {
        NSScreen.screens.first { $0.hasNotch }
    }

    var hasNotch: Bool {
        safeAreaInsets.top > 0
    }

    /// Прямоугольник челки в глобальных координатах.
    ///
    /// На экране с челкой он вычисляется как зазор между левой и правой
    /// вспомогательными областями меню-бара. На экране без челки берём
    /// виртуальный якорь по центру верхней кромки.
    ///
    /// Высоту берём из `safeAreaInsets.top`, а не из `NSStatusBar.system.thickness`:
    /// на Tahoe второй всё ещё возвращает 24 при реальных ~31.
    var anchorRect: NSRect {
        let topEdge = frame.maxY

        if let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea {
            let width = right.minX - left.maxX
            if width > 1 {
                let height = max(safeAreaInsets.top, left.height)
                return NSRect(x: left.maxX, y: topEdge - height, width: width, height: height)
            }
        }

        let height = max(safeAreaInsets.top, 31)
        let width: CGFloat = 190
        return NSRect(x: frame.midX - width / 2, y: topEdge - height, width: width, height: height)
    }
}
