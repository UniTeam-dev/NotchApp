import AppKit
import Combine

/// Иконка в меню-баре. Нужна как запасной путь: если панель почему-то не
/// раскрывается (полноэкранный режим, чужой оверлей), отсюда её можно открыть.
final class StatusItemController {
    private let item: NSStatusItem
    private let onOpen: (NotchTab) -> Void
    private let onQuit: () -> Void
    private var cancellables = Set<AnyCancellable>()

    init(agents: AgentStore, onOpen: @escaping (NotchTab) -> Void, onQuit: @escaping () -> Void) {
        self.onOpen = onOpen
        self.onQuit = onQuit
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureButton(attention: 0)
        item.menu = buildMenu()

        // Счётчик ждущих сессий дублируется в меню-баре: панель закрыта чаще, чем открыта.
        agents.$sessions
            .receive(on: RunLoop.main)
            .sink { [weak self] sessions in
                self?.configureButton(attention: sessions.filter(\.requiresAttention).count)
            }
            .store(in: &cancellables)
    }

    private func configureButton(attention: Int) {
        guard let button = item.button else { return }
        let symbol = attention > 0 ? "bell.badge.fill" : "rectangle.topthird.inset.filled"
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "NotchApp")
        button.image?.isTemplate = true
        button.title = attention > 0 ? " \(attention)" : ""
        button.imagePosition = attention > 0 ? .imageLeading : .imageOnly
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        for tab in NotchTab.allCases {
            let menuItem = NSMenuItem(title: tab.title, action: #selector(openTab(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = tab.rawValue
            menu.addItem(menuItem)
        }

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Выйти", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    @objc private func openTab(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let tab = NotchTab(rawValue: raw) else { return }
        onOpen(tab)
    }

    @objc private func quit() {
        onQuit()
    }
}
