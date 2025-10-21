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
                let remaining = formatRemainingTime(until: deadline)
                statusItem.title = "Active for: \(remaining)"
            } else {
                statusItem.title = "Active"
            }
        } else {
            statusItem.title = "Inactive"
        }
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        
        // --- Extend Timer (only when active with deadline) ---
        if coordinator.assertion.isActive && coordinator.deadline != nil {
            let extendItem = NSMenuItem(title: "Add 1 Hour", action: #selector(extendTimer), keyEquivalent: "")
            extendItem.target = self
            menu.addItem(extendItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // --- Toggle Item ---
        if coordinator.assertion.isActive {
            toggleItem.title = "Turn Off"
            toggleItem.action = #selector(turnOff)
        } else {
            let defaultDuration = DurationConfiguration.getDefaultDuration()
            if defaultDuration > 0 {
                let durationText = formatDuration(minutes: defaultDuration)
                toggleItem.title = "Activate for \(durationText)"
            } else if defaultDuration == 0 {
                toggleItem.title = "Activate Indefinitely"
            } else {
                toggleItem.title = "Activate Until End of Day"
            }
            toggleItem.action = #selector(turnOn)
        }
        toggleItem.target = self
        menu.addItem(toggleItem)

        // --- Activation Submenu ---
        let activateMenu = NSMenu()
        
        // Use centralized duration configuration
        for option in DurationConfiguration.allOptions {
            let item = NSMenuItem(title: option.menuName, action: #selector(durationSelected(_:)), keyEquivalent: "")
            item.target = self
            item.tag = option.minutes
            activateMenu.addItem(item)
        }

        let activateItem = NSMenuItem(title: "Activate for…", action: nil, keyEquivalent: "")
        activateItem.submenu = activateMenu
        menu.addItem(activateItem)
        
        menu.addItem(NSMenuItem.separator())

        // --- Settings ---
        let smartItem = NSMenuItem(title: "Respect Display Sleep", action: #selector(toggleSmart), keyEquivalent: "")
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
        if sender.tag == -1 {
            // Special case: Until End of Day
            endOfDay()
        } else {
            let deadline = clock.now.addingTimeInterval(TimeInterval(sender.tag * 60))
            coordinator.send(.userSelected(.until(deadline)))
        }
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
        activateWithDefaultDuration()
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
        let durationInMinutes = DurationConfiguration.getDefaultDuration()
        if durationInMinutes > 0 {
            let deadline = clock.now.addingTimeInterval(TimeInterval(durationInMinutes * 60))
            coordinator.send(.userSelected(.until(deadline)))
        } else if durationInMinutes == 0 {
            coordinator.send(.userSelected(.indefinitely))
        } else {
            endOfDay()
        }
    }

    @objc private func extendTimer() {
        guard let currentDeadline = coordinator.deadline else { return }
        
        // Add 1 hour to the current deadline
        let newDeadline = currentDeadline.addingTimeInterval(3600) // 1 hour in seconds
        coordinator.send(.userSelected(.until(newDeadline)))
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
    
    // MARK: - Time Formatting
    
    private func formatDuration(minutes: Int) -> String {
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes > 0 {
                return "\(hours)h \(remainingMinutes)m"
            } else {
                return "\(hours)h"
            }
        } else {
            return "\(minutes)m"
        }
    }
    
    private func formatRemainingTime(until deadline: Date) -> String {
        let now = clock.now
        let remainingSeconds = deadline.timeIntervalSince(now)
        
        guard remainingSeconds > 0 else { return "0s" }
        
        let totalSeconds = Int(remainingSeconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            // More than 1 hour: show "Xh Ym" format
            if minutes > 0 {
                return "\(hours)h \(minutes)m"
            } else {
                return "\(hours)h"
            }
        } else if minutes > 0 {
            // Less than 1 hour but more than 1 minute: show only minutes
            return "\(minutes)m"
        } else {
            // Less than 1 minute: show seconds
            return "\(seconds)s"
        }
    }

    @objc private func stateChanged() {
        updateIcon()
        
        displayTimer?.invalidate()
        if coordinator.assertion.isActive, coordinator.deadline != nil {
            let isLastMinute = isInLastMinute()
            let timerInterval = isLastMinute ? 0.05 : 1.0
            
            displayTimer = Timer.scheduledTimer(withTimeInterval: timerInterval, repeats: true) { [weak self] _ in
                self?.updateMenu()
                self?.updateIcon()
            }
        }
    }

    @objc private func updateIcon() {
        let now = clock.now
        let deadline = coordinator.deadline
        let isExpired = deadline.map { now >= $0 } ?? false
        
        if isExpired, coordinator.assertion.isActive {
            coordinator.send(.timerFired)
            return
        }
        
        let shouldShowActive = coordinator.assertion.isActive
        let iconName = shouldShowActive ? "sun.max.fill" : "moon.zzz.fill"
        
        guard let image = NSImage(systemSymbolName: iconName, accessibilityDescription: "NoDoze") else {
            item.button?.image = nil
            return
        }
        
        if shouldShowActive, coordinator.deadline != nil {
            item.button?.image = createProgressIcon(baseImage: image)
        } else {
            image.isTemplate = true
            item.button?.image = image
        }
    }
    
    private func createProgressIcon(baseImage: NSImage?) -> NSImage? {
        guard let baseImage = baseImage else { return nil }
        
        let size = NSSize(width: 20, height: 20)
        let compositeImage = NSImage(size: size)
        
        compositeImage.lockFocus()
        
        let progress = calculateProgress()
        let isLastMinute = isInLastMinute()
        
        let pulseIntensity: CGFloat
        if isLastMinute {
            let time = Date().timeIntervalSince1970
            let pulse = sin(time * 8) * 0.5 + 0.5
            pulseIntensity = pulse
        } else {
            pulseIntensity = 0
        }
        
        if progress > 0 {
            let rect = NSRect(x: 1, y: 1, width: 18, height: 18)
            let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
            
            let baseColor: NSColor
            if progress > 0.5 {
                baseColor = NSColor.systemYellow
            } else if progress > 0.2 {
                baseColor = NSColor.systemOrange
            } else {
                baseColor = NSColor.systemRed
            }
            
            let color: NSColor
            if isLastMinute {
                if progress > 0.5 {
                    let alpha = 0.6 + pulseIntensity * 0.4
                    color = baseColor.withAlphaComponent(alpha)
                } else if progress > 0.2 {
                    let transition = pulseIntensity * 0.8
                    if transition > 0.5 {
                        let yellowAlpha = (transition - 0.5) * 2
                        let orangeAlpha = 1.0 - yellowAlpha
                        color = NSColor.systemOrange.withAlphaComponent(0.6 + orangeAlpha * 0.4)
                    } else {
                        let alpha = 0.6 + transition * 0.4
                        color = baseColor.withAlphaComponent(alpha)
                    }
                } else {
                    let transition = pulseIntensity * 0.8
                    if transition > 0.5 {
                        let orangeAlpha = (transition - 0.5) * 2
                        color = NSColor.systemOrange.withAlphaComponent(0.6 + orangeAlpha * 0.4)
                    } else {
                        let alpha = 0.6 + transition * 0.4
                        color = baseColor.withAlphaComponent(alpha)
                    }
                }
            } else {
                color = baseColor
            }
            
            if isLastMinute {
                let glowAlpha = 0.1 + pulseIntensity * 0.3
                let glowColor = baseColor.withAlphaComponent(glowAlpha)
                glowColor.setFill()
                path.fill()
            }
            
            let borderColor = color.withAlphaComponent(0.7)
            borderColor.setStroke()
            path.lineWidth = 1.5
            path.stroke()
            
            let fillRect = NSRect(
                x: rect.minX + 1,
                y: rect.minY + 1,
                width: (rect.width - 2) * progress,
                height: rect.height - 2
            )
            
            if progress > 0 {
                let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 2, yRadius: 2)
                
                let fillColor: NSColor
                if isLastMinute {
                    if progress > 0.5 {
                        let alpha = 0.7 + pulseIntensity * 0.3
                        fillColor = baseColor.withAlphaComponent(alpha)
                    } else if progress > 0.2 {
                        let transition = pulseIntensity * 0.8
                        if transition > 0.5 {
                            let yellowAlpha = (transition - 0.5) * 2
                            let orangeAlpha = 1.0 - yellowAlpha
                            fillColor = NSColor.systemOrange.withAlphaComponent(0.7 + orangeAlpha * 0.3)
                        } else {
                            let alpha = 0.7 + transition * 0.3
                            fillColor = baseColor.withAlphaComponent(alpha)
                        }
                    } else {
                        let transition = pulseIntensity * 0.8
                        if transition > 0.5 {
                            let orangeAlpha = (transition - 0.5) * 2
                            fillColor = NSColor.systemOrange.withAlphaComponent(0.7 + orangeAlpha * 0.3)
                        } else {
                            let alpha = 0.7 + transition * 0.3
                            fillColor = baseColor.withAlphaComponent(alpha)
                        }
                    }
                } else {
                    fillColor = color
                }
                
                fillColor.setFill()
                fillPath.fill()
            }
        }
        
        let iconSize: CGFloat = 12
        let iconX = (size.width - iconSize) / 2
        let iconY = (size.height - iconSize) / 2
        let iconRect = NSRect(x: iconX, y: iconY, width: iconSize, height: iconSize)
        
        let pointConfig = NSImage.SymbolConfiguration(pointSize: iconSize, weight: .semibold)
        let paletteConfig = NSImage.SymbolConfiguration(paletteColors: [.white])
        let combinedConfig = pointConfig.applying(paletteConfig)
        let configuredSymbol = baseImage.withSymbolConfiguration(combinedConfig) ?? baseImage
        configuredSymbol.isTemplate = false
        configuredSymbol.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        
        compositeImage.unlockFocus()
        compositeImage.isTemplate = false
        
        return compositeImage
    }
    
    private func calculateProgress() -> Double {
        guard let deadline = coordinator.deadline,
              let acquiredAt = coordinator.assertionAcquiredAt else {
            return 0
        }
        
        let totalDuration = deadline.timeIntervalSince(acquiredAt)
        guard totalDuration > 0 else { return 0 }
        
        let remaining = deadline.timeIntervalSince(clock.now)
        let ratio = remaining / totalDuration
        return max(0, min(1, ratio))
    }
    
    private func isInLastMinute() -> Bool {
        guard let deadline = coordinator.deadline else { return false }
        let now = clock.now
        let remainingSeconds = deadline.timeIntervalSince(now)
        return remainingSeconds <= 60 && remainingSeconds > 0
    }
}
