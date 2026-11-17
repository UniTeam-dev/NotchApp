import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let music = MusicModel()
    private let shelf = ShelfStore()
    private let agents = AgentStore()
    private let commands = CommandStore()
    private let git = GitStore()
    private let keepAwake = KeepAwake()
    private let settings = AppSettings()
    private let updater = Updater()

    private var notch: NotchController?
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Paths.ensureDirectories()

        let controller = NotchController(music: music, shelf: shelf, agents: agents, commands: commands, git: git, keepAwake: keepAwake, settings: settings, updater: updater)
        controller.start()
        notch = controller

        statusItem = StatusItemController(
            agents: agents,
            settings: settings,
            onOpen: { [weak controller] tab in controller?.open(tab: tab) },
            onOpenSettings: { [weak controller] in controller?.openSettings() },
            onQuit: { NSApp.terminate(nil) }
        )

        music.start()
        shelf.load()
        commands.load()
        commands.startAutostart()
        git.refresh()
        agents.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        music.stop()
        agents.stop()
        commands.cancelAll()
        notch?.stop()
    }
}
