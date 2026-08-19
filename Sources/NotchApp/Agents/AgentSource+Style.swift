import SwiftUI

/// Визуальная идентичность IDE для подсветки «Аура».
/// Цвет = состояние агента (`AgentState.color`), оттенок = IDE (здесь).
extension AgentSource {
    /// Тёплый или холодный оттенок, которым подсветка отличает источник сессии.
    var tint: Color {
        switch self {
        case .claude: return Color(red: 0.88, green: 0.54, blue: 0.37) // тёплый коралл
        case .cursor: return Color(red: 0.81, green: 0.85, blue: 0.89) // холодный лёд
        case .cloud:  return Color(red: 0.55, green: 0.60, blue: 0.70)
        }
    }

    /// Компактная иконка IDE для строки сессии и закрытой челки.
    var mark: String {
        switch self {
        case .claude: return "asterisk"
        case .cursor: return "cube.fill"
        case .cloud:  return "cloud.fill"
        }
    }
}
