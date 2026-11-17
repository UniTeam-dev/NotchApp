import AppKit
import Combine

/// Иконка в меню-баре. Нужна как запасной путь: если панель почему-то не
/// раскрывается (полноэкранный режим, чужой оверлей), отсюда её можно открыть.
///
/// Наследуемся от `NSObject` не для красоты: `NSMenuDelegate` — объектный
/// протокол, и без этого конформанс не соберётся.
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let agents: AgentStore
    private let settings: AppSettings
    private let onOpen: (NotchTab) -> Void
    private let onOpenSettings: () -> Void
    private var tabItems: [NotchTab: NSMenuItem] = [:]
    private let onQuit: () -> Void
    private var cancellables = Set<AnyCancellable>()

    private let launchItem = NSMenuItem(
        title: "Запускать при входе",
        action: #selector(StatusItemController.toggleLaunchAtLogin),
        keyEquivalent: ""
    )

    private let clearDoneItem = NSMenuItem(
        title: "Убрать завершённые",
        action: #selector(StatusItemController.clearDone),
        keyEquivalent: ""
    )

    init(agents: AgentStore, settings: AppSettings, onOpen: @escaping (NotchTab) -> Void, onOpenSettings: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.agents = agents
        self.settings = settings
        self.onOpen = onOpen
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureButton(attention: 0, done: 0)
        item.menu = buildMenu()

        // Счётчики дублируются в меню-баре: панель закрыта чаще, чем открыта.
        // Раздел «Агенты» скрыт — счётчики в меню-баре тоже молчат.
        agents.$sessions
            .combineLatest(settings.$hiddenTabs)
            .receive(on: RunLoop.main)
            .sink { [weak self] sessions, hidden in
                let shown = hidden.contains(.agents) ? [] : sessions
                self?.configureButton(
                    attention: shown.filter { $0.requiresAttention }.count,
                    done: shown.filter { $0.awaitsVisit }.count
                )
            }
            .store(in: &cancellables)
    }

    /// Приоритет тот же, что у ауры: вопрос важнее готовности, готовность
    /// важнее тишины. Завершённые показываем до тех пор, пока в них не зайдут.
    private func configureButton(attention: Int, done: Int) {
        guard let button = item.button else { return }

        let symbol: String
        let count: Int

        if attention > 0 {
            symbol = "bell.badge.fill"
            count = attention
        } else if done > 0 {
            symbol = "checkmark.circle.fill"
            count = done
        } else {
            symbol = "rectangle.topthird.inset.filled"
            count = 0
        }

        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "NotchApp")
        button.image?.isTemplate = true
        button.title = count > 0 ? " \(count)" : ""
        button.imagePosition = count > 0 ? .imageLeading : .imageOnly
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        // Иначе AppKit включает пункты сам, и «убрать завершённые» не удастся
        // погасить, когда убирать нечего.
        menu.autoenablesItems = false

        for tab in NotchTab.allCases {
            let menuItem = NSMenuItem(title: tab.title, action: #selector(openTab(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = tab.rawValue
            menu.addItem(menuItem)
            tabItems[tab] = menuItem
        }

        let settingsItem = NSMenuItem(title: "Настройки…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        clearDoneItem.target = self
        menu.addItem(clearDoneItem)

        let diagnostics = NSMenuItem(
            title: "Скопировать дерево Claude (диагностика)",
            action: #selector(copyDiagnostics),
            keyEquivalent: ""
        )
        diagnostics.target = self
        menu.addItem(diagnostics)

        menu.addItem(.separator())

        launchItem.target = self
        menu.addItem(launchItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Выйти", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    /// Состояние автозапуска может поменяться мимо нас — через «Системные
    /// настройки», — поэтому читаем его каждый раз при открытии меню,
    /// а не запоминаем.
    func menuNeedsUpdate(_ menu: NSMenu) {
        for (tab, menuItem) in tabItems {
            menuItem.isHidden = !settings.isVisible(tab)
        }

        launchItem.state = LaunchAtLogin.isEnabled ? .on : .off
        launchItem.title = LaunchAtLogin.needsApproval
            ? "Запускать при входе — нужно разрешение"
            : "Запускать при входе"

        let done = agents.awaitingVisitCount
        clearDoneItem.isEnabled = done > 0
        clearDoneItem.title = done > 0 ? "Убрать завершённые (\(done))" : "Убрать завершённые"
    }

    @objc private func openTab(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let tab = NotchTab(rawValue: raw) else { return }
        onOpen(tab)
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func clearDone() {
        agents.dismissDone()
    }

    /// Снимок дерева Accessibility приложения Claude в буфер обмена.
    /// Нужен, чтобы подобрать правило поиска строки чата по факту.
    @objc private func copyDiagnostics() {
        let report = SessionActivator.diagnostics(for: .claude)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }

    @objc private func toggleLaunchAtLogin() {
        let wantEnabled = !LaunchAtLogin.isEnabled
        let error = LaunchAtLogin.set(wantEnabled)

        // Регистрация могла пройти, но упереться в подтверждение пользователя.
        // Молча ничего не делать тут нельзя — человек нажал и ждёт результата.
        if error != nil || (wantEnabled && LaunchAtLogin.needsApproval) {
            LaunchAtLogin.openSettings()
        }
    }

    @objc private func quit() {
        onQuit()
    }
}
