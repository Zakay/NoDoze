import Foundation
import IOKit.pwr_mgt

public final class PowerAssertionAdapter: PowerAssertion {
    private var activityToken: NSObjectProtocol?
    private var legacyID: IOPMAssertionID = 0

    public init() {}

    public func acquire(reason: String, until deadline: Date?) throws {
        guard activityToken == nil else { return }
        if #available(macOS 10.9, *) {
            let options: ProcessInfo.ActivityOptions = [.idleDisplaySleepDisabled, .idleSystemSleepDisabled]
            activityToken = ProcessInfo.processInfo.beginActivity(options: options, reason: reason)
        } else {
            let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                     IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                     reason as CFString,
                                                     &legacyID)
            guard result == kIOReturnSuccess else {
                throw NSError(domain: "NoDoze.PowerAssertion", code: Int(result), userInfo: nil)
            }
        }
    }

    public func release() {
        if #available(macOS 10.9, *) {
            if let token = activityToken {
                ProcessInfo.processInfo.endActivity(token)
            }
            activityToken = nil
        } else {
            if legacyID != 0 {
                IOPMAssertionRelease(legacyID)
                legacyID = 0
            }
        }
    }

    public var isActive: Bool {
        if #available(macOS 10.9, *) {
            return activityToken != nil
        } else {
            return legacyID != 0
        }
    }
}
