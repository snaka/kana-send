import Foundation

final class SettingsStore {
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let holdThresholdMs = "holdThresholdMs"
        static let isEnabled = "isEnabled"
        static let showIndicator = "showIndicator"
    }

    var holdThresholdMs: Int {
        get {
            let v = defaults.integer(forKey: Keys.holdThresholdMs)
            return v > 0 ? v : 500
        }
        set { defaults.set(newValue, forKey: Keys.holdThresholdMs) }
    }

    var isEnabled: Bool {
        get {
            if defaults.object(forKey: Keys.isEnabled) == nil { return true }
            return defaults.bool(forKey: Keys.isEnabled)
        }
        set { defaults.set(newValue, forKey: Keys.isEnabled) }
    }

    var showIndicator: Bool {
        get {
            if defaults.object(forKey: Keys.showIndicator) == nil { return true }
            return defaults.bool(forKey: Keys.showIndicator)
        }
        set { defaults.set(newValue, forKey: Keys.showIndicator) }
    }
}
