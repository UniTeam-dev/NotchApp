import SwiftUI

/// Настройки приложения: какие разделы панели скрыты.
final class AppSettings: ObservableObject {
    private static let key = "hiddenTabs"

    @Published private(set) var hiddenTabs: Set<NotchTab>

    init() {
        let raw = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
        hiddenTabs = Set(raw.compactMap(NotchTab.init(rawValue:)))
    }

    var visibleTabs: [NotchTab] {
        NotchTab.allCases.filter { !hiddenTabs.contains($0) }
    }

    func isVisible(_ tab: NotchTab) -> Bool {
        !hiddenTabs.contains(tab)
    }

    /// Последний раздел скрыть нельзя: панель без вкладок бессмысленна.
    func setVisible(_ tab: NotchTab, _ visible: Bool) {
        if visible {
            hiddenTabs.remove(tab)
        } else if visibleTabs.count > 1 {
            hiddenTabs.insert(tab)
        }
        UserDefaults.standard.set(hiddenTabs.map(\.rawValue), forKey: Self.key)
    }
}
