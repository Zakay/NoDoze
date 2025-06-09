import AppKit

final class StatusItemController: NSObject, NSMenuDelegate {
    private let coordinator: KeepAwakeCoordinator
    private let item: NSStatusItem
    private let menu = NSMenu()
    private let clock: Clock
    private var store: Store
    private var displayTimer: Timer?

    private let statusItem = NSMenuItem()
    private let toggleItem = NSMenuItem()

    init(coordinator: KeepAwakeCoordinator, store: Store, clock: Clock) {
        self.coordinator = coordinator
        self.store = store
        self.clock = clock
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        menu.delegate = self
        item.button?.action = #selector(itemClicked(sender:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.target = self
        updateIcon()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(stateChanged),
                                               name: .keepAwakeStateChanged,
                                               object: nil)
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateMenu()
    }

    private func updateMenu() {
        menu.removeAllItems()

        // --- Status Display ---
        if coordinator.assertion.isActive {
            if let deadline = coordinator.deadline {
                let formatter = DateComponentsFormatter()
                formatter.allowedUnits = [.hour, .minute]
                formatter.unitsStyle = .abbreviated
                let remaining = formatter.string(from: Date(), to: deadline) ?? ""
                statusItem.title = "Active for: \(remaining)"
            } else {
                statusItem.title = "Active"
            }
        } else {
            statusItem.title = "Inactive"
        }
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        menu.addItem(NSMenuItem.separator())
        
        // --- Toggle Item ---
        if coordinator.assertion.isActive {
            toggleItem.title = "Turn Off"
            toggleItem.action = #selector(turnOff)
        } else {
            toggleItem.title = "Turn On"
            toggleItem.action = #selector(turnOn)
        }
        toggleItem.target = self
        menu.addItem(toggleItem)

        // --- Activation Submenu ---
        let activateMenu = NSMenu()
        let durations = [
            ("For 1 Hour", 60),
            ("For 2 Hours", 120),
            ("For 5 Hours", 300)
        ]
        for (title, minutes) in durations {
            let item = NSMenuItem(title: title, action: #selector(durationSelected(_:)), keyEquivalent: "")
            item.target = self
            item.tag = minutes
            activateMenu.addItem(item)
        }
        let eodItem = NSMenuItem(title: "Until End of Day", action: #selector(endOfDay), keyEquivalent: "")
        eodItem.target = self
        activateMenu.addItem(eodItem)

        let activateItem = NSMenuItem(title: "Activate for…", action: nil, keyEquivalent: "")
        activateItem.submenu = activateMenu
        menu.addItem(activateItem)
        
        menu.addItem(NSMenuItem.separator())

        // --- Settings ---
        let smartItem = NSMenuItem(title: "Intelligent Mode", action: #selector(toggleSmart), keyEquivalent: "")
        smartItem.target = self
        smartItem.state = coordinator.isSmartModeEnabled ? .on : .off
        menu.addItem(smartItem)
        
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(AppDelegate.showSettings), keyEquivalent: ",")
        settingsItem.target = NSApp.delegate
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // --- Quit ---
        let quitItem = NSMenuItem(title: "Quit NoDoze", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func durationSelected(_ sender: NSMenuItem) {
        let deadline = clock.now.addingTimeInterval(TimeInterval(sender.tag * 60))
        coordinator.send(.userSelected(.until(deadline)))
    }

    @objc private func endOfDay() {
        var comps = Calendar.current.dateComponents(in: TimeZone.current, from: clock.now)
        comps.hour = 23
        comps.minute = 59
        comps.second = 0
        if let date = Calendar.current.date(from: comps) {
            coordinator.send(.userSelected(.until(date)))
        }
    }

    @objc private func turnOn() {
        coordinator.send(.userSelected(.indefinitely))
    }

    @objc private func turnOff() {
        coordinator.send(.userSelected(.off))
    }

    @objc private func toggleSmart(_ sender: NSMenuItem) {
        let newValue = !coordinator.isSmartModeEnabled
        store[Preferences.smartMode] = newValue // Persist for next launch
        coordinator.send(.smartModeToggled(newValue))
    }

    @objc private func itemClicked(sender: NSStatusBarButton) {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            item.menu = menu
            item.button?.performClick(nil)
            DispatchQueue.main.async { [weak self] in
                self?.item.menu = nil
            }
        } else {
            if coordinator.assertion.isActive {
                turnOff()
            } else {
                activateWithDefaultDuration()
            }
        }
    }

    private func activateWithDefaultDuration() {
        let durationInMinutes = UserDefaults.standard.integer(forKey: "defaultActivationDuration")
        if durationInMinutes > 0 {
            let deadline = clock.now.addingTimeInterval(TimeInterval(durationInMinutes * 60))
            coordinator.send(.userSelected(.until(deadline)))
        } else {
            coordinator.send(.userSelected(.indefinitely))
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func stateChanged() {
        updateIcon()
        
        displayTimer?.invalidate()
        if coordinator.assertion.isActive, coordinator.deadline != nil {
            displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.updateMenu()
            }
        }
    }

    @objc private func updateIcon() {
        let iconName = coordinator.assertion.isActive ? "sun.max.fill" : "moon.zzz.fill"
        let image = NSImage(systemSymbolName: iconName, accessibilityDescription: "NoDoze")
        image?.isTemplate = true
        item.button?.image = image
    }
}
