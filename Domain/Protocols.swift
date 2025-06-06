import Foundation

public protocol Cancellable {
    func cancel()
}

public protocol PowerAssertion {
    func acquire(reason: String, until deadline: Date?) throws
    func release()
    var isActive: Bool { get }
}

public protocol ScreenObserver {
    var screensDidSleep: AsyncStream<Void> { get }
    var screensDidWake: AsyncStream<Void> { get }
    func allDisplaysAsleep() -> Bool
}

public protocol Clock {
    var now: Date { get }
    func schedule(after interval: TimeInterval, _ block: @escaping () -> Void) -> Cancellable
}

public protocol Store {
    subscript<T: Codable>(key: Pref<T>) -> T { get set }
}
