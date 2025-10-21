import Foundation

public enum Preferences {
    public static let smartMode = Pref<Bool>("smartMode", default: true)
    public static let defaultActivationDuration = Pref<Int>("defaultActivationDuration", default: 60)
    public static let activateOnLaunch = Pref<Bool>("activateOnLaunch", default: false)
}

// MARK: - Duration Configuration

public struct DurationOption {
    public let name: String
    public let menuName: String
    public let minutes: Int
    public let isDefault: Bool
    
    public init(name: String, menuName: String? = nil, minutes: Int, isDefault: Bool = false) {
        self.name = name
        self.menuName = menuName ?? "For \(name)"
        self.minutes = minutes
        self.isDefault = isDefault
    }
}

public struct DurationConfiguration {
    public static let allOptions: [DurationOption] = [
        DurationOption(name: "1 Hour", minutes: 60, isDefault: true),
        DurationOption(name: "2 Hours", minutes: 120),
        DurationOption(name: "5 Hours", minutes: 300),
        DurationOption(name: "Until End of Day", menuName: "Until End of Day", minutes: -1) // Special case
    ]
    
    public static var defaultOption: DurationOption {
        // Return the option marked as default, or 1 Hour if none found
        return allOptions.first { $0.isDefault } ?? allOptions.first { $0.minutes == 60 } ?? allOptions[0]
    }
    
    public static func getDefaultDuration() -> Int {
        let defaults = UserDefaults.standard
        let key = Preferences.defaultActivationDuration.raw
        if defaults.object(forKey: key) == nil {
            return defaultOption.minutes
        }
        // Preserve stored values (including 0 for indefinite or negative sentinels).
        return defaults.integer(forKey: key)
    }
    
    public static func setDefaultDuration(_ minutes: Int) {
        UserDefaults.standard.set(minutes, forKey: Preferences.defaultActivationDuration.raw)
    }
}
