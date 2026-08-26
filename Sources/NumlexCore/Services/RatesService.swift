import Foundation

// MARK: - Snapshot & validation

/// One persisted rate table plus the time it was last successfully
/// fetched. This is the unit of the on-disk cache (atomic write +
/// rename), so a crashed write can never corrupt the previous table.
public struct RateSnapshot: Codable, Equatable, Sendable {
    public let base: String
    public let rates: [String: Double]
    public let fetchedAt: Date

    public init(base: String, rates: [String: Double], fetchedAt: Date) {
        self.base = base
        self.rates = rates
        self.fetchedAt = fetchedAt
    }

    public var ratesTable: Rates { Rates(base: base, rates: rates) }
}

/// Validates a provider rate table against the bundled fiat catalog:
/// only KNOWN ISO codes with positive finite values survive; the base
/// code must be present and is pinned to exactly 1. Returns nil when
/// the surviving table is empty, so a corrupt or off-catalog payload
/// can never become the active table.
public func validatedRates(base: String, rates: [String: Double]) -> Rates? {
    guard FiatCurrencies.codes.contains(base) else { return nil }
    var table: [String: Double] = [:]
    for (code, value) in rates {
        guard FiatCurrencies.codes.contains(code), value.isFinite, value > 0 else { continue }
        table[code] = value
    }
    guard table[base] != nil else { return nil }
    table[base] = 1
    guard table.count > 1 else { return nil }
    return Rates(base: base, rates: table)
}

/// Typed decode of the open provider document
/// (`https://open.er-api.com/v6/latest/<BASE>`). The free endpoint needs
/// no API key and publishes fiat codes only (no crypto, no metals), so
/// the bundled catalog covers everything that can arrive.
///
/// A document that fails decoding or validation yields nil from
/// `snapshot()` — the refresher then keeps serving the cached table
/// instead of publishing garbage.
public struct RateProviderDocument: Decodable, Sendable {
    public let result: String
    public let baseCode: String
    public let rates: [String: Double]
    public let timeLastUpdateUnix: Int?

    private enum CodingKeys: String, CodingKey {
        case result
        case baseCode = "base_code"
        case rates
        case timeLastUpdateUnix = "time_last_update_unix"
    }

    public var isValid: Bool {
        result == "success" && baseCode.count == 3 && !rates.isEmpty
    }

    /// The validated, base-pinned snapshot, or nil for any document that
    /// is not a clean success payload.
    public func snapshot() -> RateSnapshot? {
        guard isValid, let table = validatedRates(base: baseCode, rates: rates) else {
            return nil
        }
        let fetched = timeLastUpdateUnix.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            ?? Date()
        return RateSnapshot(base: baseCode, rates: table.rates, fetchedAt: fetched)
    }
}

// MARK: - Persistent cache

/// File-backed atomic cache of the last good `RateSnapshot`. Writes go
/// to a sibling temp file and are renamed over the cache, so readers
/// always see either the old complete table or the new complete one.
public struct RateStore: Sendable {
    public let fileURL: URL

    public init(directory: URL? = nil) {
        let dir: URL
        if let directory {
            dir = directory
        } else {
            let base = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            dir = base.appendingPathComponent("Numlex", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("rates.json")
    }

    public func load() -> RateSnapshot? {
        guard let data = try? Data(contentsOf: fileURL),
              let snap = try? JSONDecoder().decode(RateSnapshot.self, from: data),
              validatedRates(base: snap.base, rates: snap.rates) != nil else {
            return nil
        }
        return snap
    }

    @discardableResult
    public func save(_ snap: RateSnapshot) -> Bool {
        guard let data = try? JSONEncoder().encode(snap) else { return false }
        let tmp = fileURL.appendingPathExtension("tmp")
        do {
            try data.write(to: tmp, options: .atomic)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            try FileManager.default.moveItem(at: tmp, to: fileURL)
            return true
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            return false
        }
    }
}

// MARK: - Refresher

/// Single-flight currency rate refresher. `refresh()` fetches the open
/// provider endpoint, decodes and validates the document, persists the
/// snapshot atomically and serves the new table; on ANY failure (no
/// network, bad payload, decode error) it keeps serving the last good
/// table — stale but usable — and the app never blocks on rates.
public actor RateRefresher {
    /// A cached table older than this triggers a background refresh.
    public static let refreshInterval: TimeInterval = 3_600

    private let base: String
    private let url: URL?
    private let store: RateStore
    private let session: URLSession
    private var current: Rates
    private var lastUpdated: Date?
    private var isRefreshing = false

    public init(base: String = FiatCurrencies.defaultBase,
                url: URL? = nil,
                store: RateStore? = nil,
                session: URLSession = .shared) {
        self.base = base
        let explicit = url
        self.url = explicit
            ?? URL(string: "https://open.er-api.com/v6/latest/\(base)")
        let s = store ?? RateStore()
        self.store = s
        self.session = session
        if let snap = s.load() {
            self.current = snap.ratesTable
            self.lastUpdated = snap.fetchedAt
        } else {
            self.current = Rates(base: base, rates: [:])
            self.lastUpdated = nil
        }
    }

    /// The best table available right now (live or stale cache).
    public var currentRates: Rates { current }

    /// When the last successful fetch happened (nil = never).
    public var lastUpdatedAt: Date? { lastUpdated }

    /// True when the cached table is missing or older than the TTL.
    public var isStale: Bool {
        guard let at = lastUpdated else { return true }
        return Date().timeIntervalSince(at) > Self.refreshInterval
    }

    /// Fetches and validates a fresh table. Concurrent calls collapse
    /// into one in-flight fetch; failures keep the previous table.
    public func refresh() async -> Rates {
        if isRefreshing { return current }
        guard let url else { return current }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            let (data, _) = try await session.data(for: request)
            let doc = try JSONDecoder().decode(RateProviderDocument.self, from: data)
            guard let snap = doc.snapshot() else { return current }
            guard store.save(snap) else { return current }
            current = snap.ratesTable
            lastUpdated = snap.fetchedAt
        } catch {
            // Offline or malformed payload: serve the stale table.
        }
        return current
    }

    /// Test/manual hook: install a table without any network.
    public func set(_ rates: Rates) {
        current = rates
        lastUpdated = Date()
        store.save(RateSnapshot(base: rates.base, rates: rates.rates, fetchedAt: Date()))
    }
}

public extension RateRefresher {
    /// The app-wide refresher (USD-based, app-support cache).
    static var shared: RateRefresher { _shared }
    private static let _shared = RateRefresher()
}
