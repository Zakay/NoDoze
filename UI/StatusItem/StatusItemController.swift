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
            toggleItem.title = "Turn On"
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
        let durationInMinutes = DurationConfiguration.getDefaultDuration()
        if durationInMinutes > 0 {
            let deadline = clock.now.addingTimeInterval(TimeInterval(durationInMinutes * 60))
            coordinator.send(.userSelected(.until(deadline)))
        } else {
            coordinator.send(.userSelected(.indefinitely))
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
            // Check if we're in the last minute to determine timer frequency
            let isLastMinute = isInLastMinute()
            let timerInterval = isLastMinute ? 0.05 : 1.0 // 20Hz for last minute, 1Hz otherwise
            
            displayTimer = Timer.scheduledTimer(withTimeInterval: timerInterval, repeats: true) { [weak self] _ in
                self?.updateMenu()
                self?.updateIcon() // Update progress indicator and pulsing every timer tick
            }
        }
    }

    @objc private func updateIcon() {
        let iconName = coordinator.assertion.isActive ? "sun.max.fill" : "moon.zzz.fill"
        let image = NSImage(systemSymbolName: iconName, accessibilityDescription: "NoDoze")
        
        if coordinator.assertion.isActive && coordinator.deadline != nil {
            // Create a composite image with progress indicator
            item.button?.image = createProgressIcon(baseImage: image)
        } else {
            // Use template for normal state
            image?.isTemplate = true
            item.button?.image = image
        }
    }
    
    private func createProgressIcon(baseImage: NSImage?) -> NSImage? {
        guard let baseImage = baseImage else { return nil }
        
        // Use a size that works well with the menubar
        let size = NSSize(width: 20, height: 20)
        let compositeImage = NSImage(size: size)
        
        compositeImage.lockFocus()
        
        // Calculate progress
        let progress = calculateProgress()
        let isLastMinute = isInLastMinute()
        
        // Calculate pulsing effect for last minute - ANIMATION
        let pulseIntensity: CGFloat
        if isLastMinute {
            let time = Date().timeIntervalSince1970
            let pulse = sin(time * 8) * 0.5 + 0.5 // 4Hz for a pleasant animation
            pulseIntensity = pulse
        } else {
            pulseIntensity = 0
        }
        
        // Draw background progress indicator
        if progress > 0 {
            // Create a more prominent background
            let rect = NSRect(x: 1, y: 1, width: 18, height: 18)
            let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
            
            // Base colors
            let baseColor: NSColor
            if progress > 0.5 {
                baseColor = NSColor.systemYellow
            } else if progress > 0.2 {
                baseColor = NSColor.systemOrange
            } else {
                baseColor = NSColor.systemRed
            }
            
            // Apply pulsing effect to the primary color - SMOOTH GRADIENTS
            let color: NSColor
            if isLastMinute {
                // Create smooth gradient transitions using alpha blending
                if progress > 0.5 {
                    // Yellow with smooth brightness gradient
                    let alpha = 0.6 + pulseIntensity * 0.4 // Smooth alpha gradient
                    color = baseColor.withAlphaComponent(alpha)
                } else if progress > 0.2 {
                    // Orange with smooth transition to yellow
                    let transition = pulseIntensity * 0.8 // Smooth transition factor
                    if transition > 0.5 {
                        // Blend between orange and yellow
                        let yellowAlpha = (transition - 0.5) * 2 // 0 to 1
                        let orangeAlpha = 1.0 - yellowAlpha
                        color = NSColor.systemOrange.withAlphaComponent(0.6 + orangeAlpha * 0.4)
                    } else {
                        // Pure orange with brightness
                        let alpha = 0.6 + transition * 0.4
                        color = baseColor.withAlphaComponent(alpha)
                    }
                } else {
                    // Red with smooth transition to orange
                    let transition = pulseIntensity * 0.8 // Smooth transition factor
                    if transition > 0.5 {
                        // Blend between red and orange
                        let orangeAlpha = (transition - 0.5) * 2 // 0 to 1
                        let redAlpha = 1.0 - orangeAlpha
                        color = NSColor.systemOrange.withAlphaComponent(0.6 + orangeAlpha * 0.4)
                    } else {
                        // Pure red with brightness
                        let alpha = 0.6 + transition * 0.4
                        color = baseColor.withAlphaComponent(alpha)
                    }
                }
            } else {
                color = baseColor
            }
            
            // Background glow effect - SMOOTH GRADIENT
            if isLastMinute {
                let glowAlpha = 0.1 + pulseIntensity * 0.3 // Smooth background gradient
                let glowColor = baseColor.withAlphaComponent(glowAlpha)
                glowColor.setFill()
                path.fill()
            }
            
            // Draw the border first (darker version of the color)
            let borderColor = color.withAlphaComponent(0.7)
            borderColor.setStroke()
            path.lineWidth = 1.5
            path.stroke()
            
            // Draw the progress fill (only the filled portion) - SMOOTH GRADIENTS
            let fillRect = NSRect(
                x: rect.minX + 1,
                y: rect.minY + 1,
                width: (rect.width - 2) * progress,
                height: rect.height - 2
            )
            
            if progress > 0 {
                let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 2, yRadius: 2)
                
                // Apply pulsing to the fill color as well - SMOOTH GRADIENTS
                let fillColor: NSColor
                if isLastMinute {
                    // Create smooth fill color gradients
                    if progress > 0.5 {
                        // Yellow fill - smooth brightness gradient
                        let alpha = 0.7 + pulseIntensity * 0.3
                        fillColor = baseColor.withAlphaComponent(alpha)
                    } else if progress > 0.2 {
                        // Orange fill - smooth transition to yellow
                        let transition = pulseIntensity * 0.8
                        if transition > 0.5 {
                            // Blend between orange and yellow
                            let yellowAlpha = (transition - 0.5) * 2
                            let orangeAlpha = 1.0 - yellowAlpha
                            fillColor = NSColor.systemOrange.withAlphaComponent(0.7 + orangeAlpha * 0.3)
                        } else {
                            // Pure orange with brightness
                            let alpha = 0.7 + transition * 0.3
                            fillColor = baseColor.withAlphaComponent(alpha)
                        }
                    } else {
                        // Red fill - smooth transition to orange
                        let transition = pulseIntensity * 0.8
                        if transition > 0.5 {
                            // Blend between red and orange
                            let orangeAlpha = (transition - 0.5) * 2
                            let redAlpha = 1.0 - orangeAlpha
                            fillColor = NSColor.systemOrange.withAlphaComponent(0.7 + orangeAlpha * 0.3)
                        } else {
                            // Pure red with brightness
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
        
        // Draw the icon on top - center it properly
        let iconSize: CGFloat = 12
        let iconX = (size.width - iconSize) / 2
        let iconY = (size.height - iconSize) / 2
        let iconRect = NSRect(x: iconX, y: iconY, width: iconSize, height: iconSize)
        
        // Draw a proper white sun icon manually - NO PULSING
        NSColor.white.set()
        
        let centerX = iconRect.midX
        let centerY = iconRect.midY
        let innerRadius: CGFloat = 2.5
        let rayStartRadius: CGFloat = 3.5
        let rayEndRadius: CGFloat = 5.5
        
        // Draw the main sun circle first
        let sunCircle = NSBezierPath(ovalIn: NSRect(x: centerX - innerRadius, y: centerY - innerRadius, width: innerRadius * 2, height: innerRadius * 2))
        sunCircle.fill()
        
        // Draw sun rays as separate lines that don't connect to the circle
        for i in 0..<8 {
            let angle = Double(i) * .pi / 4
            let rayStartX = centerX + cos(angle) * rayStartRadius
            let rayStartY = centerY + sin(angle) * rayStartRadius
            let rayEndX = centerX + cos(angle) * rayEndRadius
            let rayEndY = centerY + sin(angle) * rayEndRadius
            
            // Create a simple straight ray line
            let rayPath = NSBezierPath()
            rayPath.move(to: NSPoint(x: rayStartX, y: rayStartY))
            rayPath.line(to: NSPoint(x: rayEndX, y: rayEndY))
            
            rayPath.lineWidth = 1.5
            rayPath.stroke()
        }
        
        compositeImage.unlockFocus()
        
        return compositeImage
    }
    
    private func calculateProgress() -> Double {
        guard let deadline = coordinator.deadline else { return 0 }
        guard let acquiredAt = coordinator.assertionAcquiredAt else { return 0 }
        
        let now = clock.now
        let totalDuration = deadline.timeIntervalSince(acquiredAt)
        let remaining = deadline.timeIntervalSince(now)
        
        guard totalDuration > 0 else { return 0 }
        
        let progress = max(0, min(1, remaining / totalDuration))
        return progress
    }
    
    private func isInLastMinute() -> Bool {
        guard let deadline = coordinator.deadline else { return false }
        let now = clock.now
        let remainingSeconds = deadline.timeIntervalSince(now)
        return remainingSeconds <= 60 && remainingSeconds > 0
    }
}
