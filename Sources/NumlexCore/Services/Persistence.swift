import Foundation

public struct StorePayload: Codable {
    public var sheets: [Sheet]
    public var selectedIndex: Int
    public var settings: AppSettings
    public var version: Int
    public init(sheets: [Sheet], selectedIndex: Int, settings: AppSettings, version: Int = 1) {
        self.sheets = sheets
        self.selectedIndex = selectedIndex
        self.settings = settings
        self.version = version
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
