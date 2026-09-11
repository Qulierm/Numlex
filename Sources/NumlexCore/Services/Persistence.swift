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
    /// r77b: isolated-data override for validation launches. The launch
    /// argument `--data-dir <path>` (or the `NUMLEX_DATA_DIR`
    /// environment variable) redirects the ENTIRE data directory
    /// (store and every cached data file the app keeps beside it) to
    /// the given path, so an instrumented validation instance can run
    /// against a temporary fixture without ever touching the user's
    /// real Application Support. Inert unless explicitly passed —
    /// normal launches always use the standard user-location folder.
    public static let dataDirOverride: URL? = {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--data-dir"), i + 1 < args.count {
            return URL(fileURLWithPath: args[i + 1], isDirectory: true)
        }
        if let env = ProcessInfo.processInfo.environment["NUMLEX_DATA_DIR"],
           !env.isEmpty {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        return nil
    }()

    /// The canonical data-directory LOCATION (see `dataDirOverride`): the
    /// standard user-location folder, or the explicit validation override
    /// directory. Pure path resolution — never creates anything.
    public static func dataDirectoryLocation() -> URL {
        if let override = dataDirOverride { return override }
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Numlex", isDirectory: true)
    }

    /// The one data directory every persisted artifact lives in.
    ///
    /// `createIfNeeded: false` is what the r97 first-launch check uses: the
    /// welcome decision must be taken BEFORE anything creates or loads the
    /// directory, or "does this directory exist / does it already carry
    /// artifacts" would be answered by the app's own side effects.
    public static func dataDirectory(createIfNeeded: Bool = true) -> URL {
        let dir = dataDirectoryLocation()
        if createIfNeeded {
            try? FileManager.default.createDirectory(at: dir,
                                                     withIntermediateDirectories: true)
        }
        return dir
    }

    public static func appSupportURL() -> URL {
        storeURL(in: dataDirectory())
    }

    /// The store file inside an explicit directory (used by the first-launch
    /// policy tests; the app itself always uses `appSupportURL()`).
    public static func storeURL(in directory: URL) -> URL {
        directory.appendingPathComponent("store.json")
    }

    public static func load() -> StorePayload? {
        load(from: dataDirectory())
    }

    public static func load(from directory: URL) -> StorePayload? {
        guard let data = try? Data(contentsOf: storeURL(in: directory)) else { return nil }
        return try? JSONDecoder().decode(StorePayload.self, from: data)
    }

    public static func save(_ payload: StorePayload) {
        save(payload, to: dataDirectory())
    }

    public static func save(_ payload: StorePayload, to directory: URL) {
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: storeURL(in: directory), options: .atomic)
        }
    }
}
