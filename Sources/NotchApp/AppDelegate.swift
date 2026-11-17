import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let music = MusicModel()
    private let shelf = ShelfStore()
    private let agents = AgentStore()
    private let commands = CommandStore()
    private let git = GitStore()
    private let keepAwake = KeepAwake()

    private var notch: NotchController?
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Paths.ensureDirectories()

        let controller = NotchController(music: music, shelf: shelf, agents: agents, commands: commands, git: git, keepAwake: keepAwake)
        controller.start()
        notch = controller

        statusItem = StatusItemController(
            agents: agents,
            onOpen: { [weak controller] tab in controller?.open(tab: tab) },
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
