import Foundation
import os

/// Единый логгер. Смотреть так:
///   log stream --predicate 'subsystem == "com.notchapp.NotchApp"' --level debug
enum Log {
    private static let subsystem = "com.notchapp.NotchApp"

    static let notch = Logger(subsystem: subsystem, category: "notch")
    static let music = Logger(subsystem: subsystem, category: "music")
    static let shelf = Logger(subsystem: subsystem, category: "shelf")
    static let agents = Logger(subsystem: subsystem, category: "agents")
}
