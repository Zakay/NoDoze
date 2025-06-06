import Foundation

public final class AssertionManager {
    private let impl: PowerAssertion
    public init(adapter: PowerAssertion) { self.impl = adapter }
    public func acquire(reason: String, until deadline: Date?) throws { try impl.acquire(reason: reason, until: deadline) }
    public func release() { impl.release() }
    public var isActive: Bool { impl.isActive }
}
