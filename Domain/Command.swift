import Foundation

enum Command {
    case acquireAssertion(until: Date?)
    case releaseAssertion
    case scheduleTimer(at: Date)
    case cancelTimer
}
