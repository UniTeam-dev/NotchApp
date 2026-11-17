import Foundation

enum NotchTab: String, CaseIterable, Identifiable, Hashable {
    case music
    case shelf
    case agents
    case git
    case terminal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .music:  return "Музыка"
        case .shelf:  return "Полка"
        case .agents: return "Агенты"
        case .git: return "Git"
        case .terminal: return "Терминал"
        }
    }

    var symbol: String {
        switch self {
        case .music:  return "waveform"
        case .shelf:  return "tray.full"
        case .agents: return "sparkles"
        case .git: return "arrow.triangle.branch"
        case .terminal: return "terminal"
        }
    }
}
