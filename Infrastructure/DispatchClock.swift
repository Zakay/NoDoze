import Foundation

public final class DispatchClock: Clock {
    public var now: Date { Date() }

    public func schedule(after interval: TimeInterval, _ block: @escaping () -> Void) -> Cancellable {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval, repeating: .never)
        timer.setEventHandler(handler: block)
        timer.resume()
        return Token(timer: timer)
    }

    private struct Token: Cancellable {
        let timer: DispatchSourceTimer
        func cancel() { timer.cancel() }
    }
}
