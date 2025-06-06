import Foundation

public struct Pref<Value: Codable> {
    public let raw: String
    public let defaultValue: Value
    public init(_ raw: String, default defaultValue: Value) {
        self.raw = raw
        self.defaultValue = defaultValue
    }
}
