import SwiftUI

/// Описание подсветки панели: какого она цвета, какого оттенка и насколько яркая.
struct NotchGlow: Equatable {
    /// Доминирующее состояние — из него берутся и цвет, и значок.
    var state: AgentState
    /// Оттенок IDE, к которому относится сессия.
    var tint: Color
    /// Источник — чтобы показать иконку IDE в закрытой челке.
    var source: AgentSource
    /// Требует ли участия человека: интенсивная «дышащая» подсветка против тихой.
    var intense: Bool
    /// Множитель яркости. «Готово» светит ровно и заметно, «работает» — фоном.
    var strength: Double

    var color: Color { state.color }
    var mark: String { state.mark }
}

extension AgentStore {
    /// Подсветка выбирается по самой важной сессии.
    ///
    /// Порядок проб — это и есть приоритет внимания. «Готово» здесь наравне с
    /// остальными: момент, когда агент закончил, — ровно тот, ради которого на
    /// челку и смотрят. И, в отличие от прежней версии, оно не гаснет по
    /// таймеру: горит, пока в сессию не перейдут.
    var glow: NotchGlow? {
        if let session = sessions.first(where: { $0.requiresAttention }) {
            return NotchGlow(session: session, intense: true, strength: 1.0)
        }
        if let session = sessions.first(where: { $0.state == .error }) {
            return NotchGlow(session: session, intense: true, strength: 1.0)
        }
        if let session = sessions.first(where: { $0.awaitsVisit }) {
            // Не «дышит»: работа кончилась, дёргать больше нечем. Но и не
            // еле-еле — иначе «готово» невозможно заметить, а именно за ним
            // человек и возвращается.
            return NotchGlow(session: session, intense: false, strength: 0.8)
        }
        if let session = sessions.first(where: { $0.state == .working }) {
            return NotchGlow(session: session, intense: false, strength: 0.45)
        }
        return nil
    }
}

private extension NotchGlow {
    init(session: AgentSession, intense: Bool, strength: Double) {
        self.init(
            state: session.state,
            tint: session.source.tint,
            source: session.source,
            intense: intense,
            strength: strength
        )
    }
}
