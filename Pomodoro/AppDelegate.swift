@preconcurrency import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: PanelController?

    public override init() {
        super.init()
    }

    public func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = makeMenu()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let shortTimers = ProcessInfo.processInfo.arguments.contains("-short-timers")
        let model = PomodoroModel(shortTimers: shortTimers)
        let controller = PanelController(model: model)
        self.controller = controller
        controller.show()
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        menu.addItem(appItem)
        let appMenu = NSMenu()
        let quit = NSMenuItem(
            title: "Quit Pomodoro",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.target = NSApp
        appMenu.addItem(quit)
        appItem.submenu = appMenu
        return menu
    }
}
