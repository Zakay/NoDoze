import AppKit
import SwiftUI

fileprivate class ContentSizedHostingController<Content: View>: NSHostingController<Content> {
    override func viewDidLayout() {
        super.viewDidLayout()
        self.view.window?.setContentSize(self.view.fittingSize)
    }
}

class SettingsWindowController: NSWindowController {
    convenience init() {
        let settingsView = SettingsView()
        let hostingController = ContentSizedHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        window.styleMask.remove(.resizable)
        window.title = "NoDoze Settings"
        self.init(window: window)
    }

    func show() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
} 