import AppKit
import SwiftUI

/// Хостинг SwiftUI внутри панели.
///
/// Окно шире видимой панели: вокруг контента есть запас (`bleed`) под свечение
/// ауры. Этот запас не должен ловить мышь, иначе панель будет считаться
/// «под курсором» далеко за своими краями. Поэтому hitTest отсекает всё,
/// что вне интерактивного прямоугольника.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    /// Интерактивная область в координатах contentView окна.
    /// nil означает «сейчас не кликабельно вообще».
    var interactiveRect: (() -> NSRect?)?

    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) не поддерживается")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let provider = interactiveRect else {
            return super.hitTest(point)
        }
        guard let rect = provider(), rect.contains(point) else {
            return nil
        }
        return super.hitTest(point)
    }
}
