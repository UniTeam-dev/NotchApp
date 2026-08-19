import SwiftUI

/// Описание подсветки панели: какого она цвета, какого оттенка и насколько яркая.
struct NotchGlow: Equatable {
    /// Цвет доминирующего состояния.
    var color: Color
    /// Оттенок IDE, к которому относится сессия.
    var tint: Color
    /// Источник — чтобы показать иконку IDE в закрытой челке.
    var source: AgentSource
    /// Требует ли участия человека: интенсивная «дышащая» подсветка против тихой.
    var intense: Bool
}

extension AgentStore {
    /// Подсветка выбирается по самой важной видимой сессии.
    /// Сессии уже отсортированы: требующие внимания — сверху.
    var glow: NotchGlow? {
        if let session = sessions.first(where: { $0.requiresAttention }) {
            return NotchGlow(
                color: session.state.color,
                tint: session.source.tint,
                source: session.source,
                intense: true
            )
        }
        if let session = sessions.first(where: { $0.state == .working }) {
            return NotchGlow(
                color: session.state.color,
                tint: session.source.tint,
                source: session.source,
                intense: false
            )
        }
        return nil
    }
}
