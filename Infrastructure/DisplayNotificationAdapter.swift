import Foundation
import AppKit
import CoreGraphics

public final class DisplayNotificationAdapter: ScreenObserver {
    public let screensDidSleep: AsyncStream<Void>
    public let screensDidWake: AsyncStream<Void>

    private var sleepContinuation: AsyncStream<Void>.Continuation!
    private var wakeContinuation: AsyncStream<Void>.Continuation!
    private var observers: [NSObjectProtocol] = []

    public init() {
        var sleepCont: AsyncStream<Void>.Continuation!
        var wakeCont: AsyncStream<Void>.Continuation!

        self.screensDidSleep = AsyncStream<Void> { continuation in
            sleepCont = continuation
        }
        self.screensDidWake = AsyncStream<Void> { continuation in
            wakeCont = continuation
        }
        self.sleepContinuation = sleepCont
        self.wakeContinuation  = wakeCont

        let wsNC = NSWorkspace.shared.notificationCenter
        observers.append(wsNC.addObserver(forName: NSWorkspace.screensDidSleepNotification,
                                          object: nil, queue: .main) { [weak self] _ in
            self?.sleepContinuation.yield()
        })
        observers.append(wsNC.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                                          object: nil, queue: .main) { [weak self] _ in
            self?.wakeContinuation.yield()
        })
    }

    public func allDisplaysAsleep() -> Bool {
        return NSScreen.screens.allSatisfy { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                return true
            }
            return CGDisplayIsAsleep(id) != 0
        }
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        for obs in observers {
            center.removeObserver(obs)
        }
        sleepContinuation.finish()
        wakeContinuation.finish()
    }
}
