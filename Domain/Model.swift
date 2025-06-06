import Foundation

struct Model {
    var mode: KeepMode = .off
    var smartEnabled: Bool
    var deadline: Date? = nil

    mutating func step(event: Event, displaysAllAsleep: Bool, now: Date) -> [Command] {
        var commands: [Command] = []

        switch event {
        case .userSelected(let newMode):
            mode = newMode
            switch mode {
            case .off:
                commands += [.releaseAssertion, .cancelTimer]
                deadline = nil
            case .until(let d):
                deadline = d
                commands += [.acquireAssertion(until: d), .scheduleTimer(at: d)]
            case .indefinitely:
                deadline = nil
                commands += [.acquireAssertion(until: nil), .cancelTimer]
            }

        case .smartModeToggled(let isEnabled):
            smartEnabled = isEnabled

        case .screensSlept:
            if smartEnabled && displaysAllAsleep && mode != .off {
                commands.append(.releaseAssertion)
            }

        case .screensWoke:
            // When waking, if we are in a mode that should be active, re-acquire the assertion.
            // If the deadline has passed while asleep, the .timerFired event will handle the
            // transition to the .off state.
            switch mode {
            case .off:
                break // Do nothing
            case .until(let d):
                if now < d {
                    commands.append(.acquireAssertion(until: d))
                }
            case .indefinitely:
                commands.append(.acquireAssertion(until: nil))
            }

        case .timerFired:
            mode = .off
            deadline = nil
            commands += [.releaseAssertion, .cancelTimer]
        }
        return commands
    }
}
