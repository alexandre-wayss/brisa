import Foundation

enum WidgetState {
    static let suiteName = "group.local.brisa.ambient"
    private static var defaults: UserDefaults {
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName) != nil,
              let sharedDefaults = UserDefaults(suiteName: suiteName) else {
            return .standard
        }
        return sharedDefaults
    }

    static func publish(isPlaying: Bool, title: String, soundCount: Int, volume: Double) {
        defaults.set(isPlaying, forKey: "widget.isPlaying")
        defaults.set(title, forKey: "widget.title")
        defaults.set(soundCount, forKey: "widget.soundCount")
        defaults.set(volume, forKey: "widget.volume")
        defaults.set(Date(), forKey: "widget.updatedAt")
    }

    static func consumePendingAction() -> String? {
        let action = defaults.string(forKey: "widget.pendingAction")
        defaults.removeObject(forKey: "widget.pendingAction")
        return action
    }
}
