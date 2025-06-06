import Foundation

public final class PersistentStore: Store {
    private let defaults: UserDefaults

    public init(suiteName: String? = nil) {
        if let name = suiteName {
            defaults = UserDefaults(suiteName: name) ?? .standard
        } else {
            defaults = .standard
        }
    }

    public subscript<T>(key: Pref<T>) -> T where T : Decodable, T : Encodable {
        get {
            if let data = defaults.data(forKey: key.raw),
               let value = try? JSONDecoder().decode(T.self, from: data) {
                return value
            }
            return key.defaultValue
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            defaults.set(data, forKey: key.raw)
        }
    }
}
