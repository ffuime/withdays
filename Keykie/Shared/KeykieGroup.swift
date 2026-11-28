import Foundation

/// Keykie's shared storage: settings in the App Group's defaults, everything else as files in its container.
/// The same code runs in WithDays (the settings screens) and in the keyboard.
enum KeykieGroup {
    static let baseIdentifier = "group.com.ffuime.withdays"

    /// SideStore / AltStore rename App Groups when they re-sign, and list the real names under `ALTAppGroups`.
    static let identifier: String? = {
        var candidates: [String] = []
        if let groups = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] {
            candidates += groups
        }
        candidates.append(baseIdentifier)
        if let bundleID = Bundle.main.bundleIdentifier {
            var appID = bundleID
            for suffix in [".keykie", ".widget", ".subsreport"] where appID.hasSuffix(suffix) {
                appID = String(appID.dropLast(suffix.count))
            }
            candidates.append("group." + appID)
        }
        return candidates.first { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil }
    }()

    static let defaults: UserDefaults = {
        let defaults = identifier.flatMap { UserDefaults(suiteName: $0) } ?? .standard
        defaults.register(defaults: KK.defaults)
        return defaults
    }()

    /// `Keykie/` in the group container (the process's own Application Support without a group).
    static let directory: URL = {
        let root = identifier.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = root.appendingPathComponent("Keykie", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func file(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    /// The converter's learning memory.
    static var memoryDirectory: URL {
        let url = directory.appendingPathComponent("Memory", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: file(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func save<T: Encodable>(_ value: T, to name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: file(name), options: .atomic)
    }

    /// Bumped whenever the app changes something the keyboard caches (dictionaries, skin image).
    static func touch() {
        defaults.set(Date().timeIntervalSince1970, forKey: KK.revision)
    }
}
