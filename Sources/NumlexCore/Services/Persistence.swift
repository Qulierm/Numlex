import Foundation

public struct StorePayload: Codable {
    public var sheets: [Sheet]
    public var selectedIndex: Int
    public var settings: AppSettings
    public var version: Int
    /// r39: one-level sidebar folders in sidebar order. Additive: pre-r39
    /// payloads without the key decode to [], and a malformed field must
    /// not discard the rest of the store.
    public var folders: [SheetFolder]

    /// r19: content in v2 stores is stored EXACTLY as typed/transformed
    /// by the user's own input preferences; loading never rewrites it.
    /// v1 stores (pre-r19) get one legacy canonicalization pass at load.
    public static let currentVersion = 2
    public init(sheets: [Sheet], selectedIndex: Int, settings: AppSettings, version: Int = 1,
                folders: [SheetFolder] = []) {
        self.sheets = sheets
        self.selectedIndex = selectedIndex
        self.settings = settings
        self.version = version
        self.folders = folders
    }

    /// Backward-compatible decode: pre-r39 payloads have no `folders`
    /// key at all and decode to []. A malformed `folders` field (wrong
    /// type or shape) falls back to [] instead of failing the decoding
    /// of the otherwise valid store. Key-by-key, like the other
    /// additive fields; version stays 2 (no migration, no rewrite).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sheets = try c.decode([Sheet].self, forKey: .sheets)
        selectedIndex = try c.decode(Int.self, forKey: .selectedIndex)
        settings = try c.decode(AppSettings.self, forKey: .settings)
        version = try c.decode(Int.self, forKey: .version)
        folders = (try? c.decodeIfPresent([SheetFolder].self, forKey: .folders)) ?? []
    }
}

public enum Persistence {
    public static func appSupportURL() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Numlex", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("store.json")
    }

    public static func load() -> StorePayload? {
        let url = appSupportURL()
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(StorePayload.self, from: data)
    }

    public static func save(_ payload: StorePayload) {
        let url = appSupportURL()
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
