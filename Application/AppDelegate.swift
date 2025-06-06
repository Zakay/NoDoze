import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: KeepAwakeCoordinator!
    private var statusController: StatusItemController!
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let assertion = PowerAssertionAdapter()
        let screens = DisplayNotificationAdapter()
        let clock = DispatchClock()
        let store = PersistentStore()

        coordinator = KeepAwakeCoordinator(assertion: assertion,
                                           screens: screens,
                                           clock: clock,
                                           store: store)
        coordinator.start()

        statusController = StatusItemController(coordinator: coordinator, store: store, clock: clock)
        
        if UserDefaults.standard.bool(forKey: "activateOnLaunch") {
            coordinator.send(.userSelected(.indefinitely))
        }
    }

    @objc func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.show()
    }
}
