import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let music = MusicModel()
    private let shelf = ShelfStore()
    private let agents = AgentStore()

    private var notch: NotchController?
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Paths.ensureDirectories()

        let controller = NotchController(music: music, shelf: shelf, agents: agents)
        controller.start()
        notch = controller

        statusItem = StatusItemController(
            agents: agents,
            onOpen: { [weak controller] tab in controller?.open(tab: tab) },
            onQuit: { NSApp.terminate(nil) }
        )

        music.start()
        shelf.load()
        agents.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        music.stop()
        agents.stop()
        notch?.stop()
    }
}
