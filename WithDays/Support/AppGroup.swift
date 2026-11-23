import Foundation

/// Settings the widgets need live in the App Group's shared defaults.
enum AppGroup {
    static let baseIdentifier = "group.com.ffuime.withdays"

    /// SideStore / AltStore rename App Groups when they re-sign the app and list the real names under
    /// `ALTAppGroups`, so every candidate is tried and the first one with a container wins.
    static let identifier: String? = {
        var candidates: [String] = []
        if let groups = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] {
            candidates += groups
        }
        candidates.append(baseIdentifier)
        if let bundleID = Bundle.main.bundleIdentifier {
            // The extensions' bundle IDs are the app's plus ".widget" / ".subsreport".
            var appID = bundleID
            for suffix in [".widget", ".subsreport"] where appID.hasSuffix(suffix) {
                appID = String(appID.dropLast(suffix.count))
            }
            candidates.append("group." + appID)
        }
        return candidates.first { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil }
    }()

    static var isAvailable: Bool { identifier != nil }

    /// Falls back to the app's own defaults when no group could be opened (the widgets then use defaults).
    static let defaults: UserDefaults = identifier.flatMap { UserDefaults(suiteName: $0) } ?? .standard

    /// Copies settings saved before the App Group existed. Runs once in the app.
    static func migrate() {
        guard defaults !== UserDefaults.standard else { return }
        let keys = [
            SettingsKey.theme, SettingsKey.weekStart, SettingsKey.hiddenCalendars,
            SettingsKey.holidayCalendar, SettingsKey.defaultCalendar,
        ]
        for key in keys where defaults.object(forKey: key) == nil {
            if let value = UserDefaults.standard.object(forKey: key) {
                defaults.set(value, forKey: key)
            }
        }
    }
}
