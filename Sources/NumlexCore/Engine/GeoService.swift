import Foundation

// MARK: - r85: geography service (geocode-only, cache, refresher)

/// r85: the geography lookup runs the Open-Meteo GEOCODING endpoint
/// only — a place is resolved to its top-ranked coordinate and NOTHING
/// else is fetched (no forecast, no key). The pure provider document
/// and URL builder are REUSED from the weather service
/// (`WeatherGeocodeDocument`, `WeatherEndpoints.geocodeURL`) so the
/// two features can never drift apart in their provider handling;
/// `WeatherRefresher`'s public behavior is untouched.
public enum GeoEndpoints {
    /// Per-request network timeout (seconds) — shared value, same
    /// discipline as the weather service.
    public static let timeout: TimeInterval = 10
    /// Response-size cap (bytes): geocode documents are small JSON.
    public static let maxResponseBytes = 256 * 1024

    /// The geocode URL for a display place (reuses the weather
    /// builder: `https://geocoding-api.open-meteo.com/v1/search?…`).
    public static func geocodeURL(for displayPlace: String) -> URL? {
        WeatherEndpoints.geocodeURL(for: displayPlace)
    }

    public static func request(for url: URL) -> URLRequest {
        var r = URLRequest(url: url)
        r.timeoutInterval = timeout
        return r
    }

    /// HTTP 2xx plus the size cap — the same validation contract as
    /// the weather service (non-HTTP responses from injected mock
    /// transports skip the status check but keep the cap).
    public static func validatedData(_ data: Data, response: URLResponse) throws -> Data {
        try WeatherEndpoints.validatedData(data, response: response)
    }
}

/// The top-ranked place of a geocode document as a validated snapshot
/// input: nil for any document that is not a clean single result.
public func geoPlace(from doc: WeatherGeocodeDocument) -> (name: String, country: String?,
                                                           lat: Double, lon: Double)? {
    guard let p = doc.top else { return nil }
    return (p.name, p.country, p.latitude, p.longitude)
}

// MARK: - Persistent cache

private struct GeoCacheFile: Codable {
    var entries: [String: GeoSnapshot] = [:]
}

/// File-backed atomic cache of last-good place coordinates by
/// canonical place key. Writes go to a sibling temp file renamed over
/// `locations.json`, so readers always see either the old complete
/// cache or the new one. A malformed file loads as empty; invalid
/// entries are dropped on load. Never stores failures — last-good
/// coordinates stay usable offline.
public struct GeoStore: Sendable {
    public let fileURL: URL

    public init(directory: URL? = nil) {
        let dir: URL
        if let directory {
            dir = directory
        } else {
            // The ONE shared data directory (honors the --data-dir
            // validation override, like the weather cache).
            dir = Persistence.dataDirectory()
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("locations.json")
    }

    /// Sanitized cache: malformed files decode as empty, invalid
    /// snapshots are dropped.
    public func load() -> [String: GeoSnapshot] {
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(GeoCacheFile.self, from: data) else {
            return [:]
        }
        return file.entries.filter { $0.value.isValid }
    }

    @discardableResult
    public func save(_ entries: [String: GeoSnapshot]) -> Bool {
        let clean = entries.filter { $0.value.isValid }
        guard let data = try? JSONEncoder().encode(GeoCacheFile(entries: clean)) else {
            return false
        }
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

/// Per-place geography refresher over Open-Meteo geocoding ONLY.
/// The in-memory cache seeds from `locations.json` at init; a
/// successful geocode validates and persists the new snapshot. ANY
/// failure keeps serving the last-good coordinate — stale but usable
/// — and a place with no cache at all resolves unavailable upstream.
/// Cancellation never corrupts the cache: a cancelled fetch installs
/// nothing.
public actor GeoRefresher {
    /// A cached coordinate older than this triggers a background
    /// refresh (30 days — place coordinates are stable).
    public static let cacheTTL: TimeInterval = 30 * 24 * 3600
    /// Bounded concurrent provider fetches (different places proceed
    /// in parallel up to this limit; same-place callers share one
    /// flight).
    public static let maxConcurrentFetches = 4

    private let store: GeoStore
    private let transport: WeatherTransport
    private let now: @Sendable () -> Date
    private var cache: [String: GeoSnapshot]
    private var inFlight: [String: (token: UUID, task: Task<GeoSnapshot?, Never>)] = [:]
    private var running = 0
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, Never>)] = []
    private var cancelledWaiters: Set<UUID> = []

    public init(store: GeoStore? = nil,
                transport: WeatherTransport? = nil,
                now: @Sendable @escaping () -> Date = Date.init) {
        let s = store ?? GeoStore()
        self.store = s
        self.transport = transport ?? { try await URLSession.shared.data(for: $0) }
        self.now = now
        self.cache = s.load()
    }

    /// The last-good coordinate for a place key, if any (stale or fresh).
    public func cachedSnapshot(forPlaceKey key: String) -> GeoSnapshot? {
        let s = cache[key]
        return (s != nil && s!.isValid) ? s : nil
    }

    /// True when the place has no cached snapshot or it is older than
    /// the TTL (evaluated against the injected clock).
    public func isStale(_ key: String) -> Bool {
        guard let s = cache[key], s.isValid else { return true }
        return now().timeIntervalSince(s.fetchedAt) > Self.cacheTTL
    }

    /// Fetches and validates the coordinate for a place. Concurrent
    /// callers for the SAME place share one in-flight fetch (true
    /// single-flight); different places run concurrently up to
    /// `maxConcurrentFetches`. Success installs and persists the new
    /// snapshot; failure returns the stale last-good snapshot (or nil
    /// when the place was never cached) and never overwrites it.
    public func refresh(displayPlace: String, placeKey: String) async -> GeoSnapshot? {
        if let t = inFlight[placeKey]?.task { return await t.value }
        let token = UUID()
        let child = Task<GeoSnapshot?, Never> {
            await self.fetchAndStore(displayPlace: displayPlace, placeKey: placeKey)
        }
        inFlight[placeKey] = (token: token, task: child)
        defer {
            if inFlight[placeKey]?.token == token {
                inFlight.removeValue(forKey: placeKey)
            }
        }
        return await withTaskCancellationHandler {
            await child.value
        } onCancel: {
            child.cancel()
        }
    }

    /// Test/manual hook: install a snapshot without any network.
    /// Invalid snapshots are refused and change nothing.
    public func inject(_ snapshot: GeoSnapshot) {
        guard snapshot.isValid else { return }
        cache[snapshot.placeKey] = snapshot
        store.save(cache)
    }

    // MARK: Internals

    private func fetchAndStore(displayPlace: String, placeKey: String) async -> GeoSnapshot? {
        await acquireSlot()
        defer { releaseSlot() }
        // A fetch cancelled before (or during) the network run installs
        // nothing: the caller keeps the pre-fetch last-good value.
        if Task.isCancelled { return cache[placeKey] }
        guard let fresh = await fetch(displayPlace: displayPlace, placeKey: placeKey) else {
            return cache[placeKey]
        }
        if Task.isCancelled { return cache[placeKey] }
        cache[placeKey] = fresh
        store.save(cache)
        return fresh
    }

    private func fetch(displayPlace: String, placeKey: String) async -> GeoSnapshot? {
        guard let url = GeoEndpoints.geocodeURL(for: displayPlace) else { return nil }
        guard let (data, resp) = try? await transport(GeoEndpoints.request(for: url)),
              let bytes = try? GeoEndpoints.validatedData(data, response: resp),
              let doc = try? JSONDecoder().decode(WeatherGeocodeDocument.self, from: bytes),
              let place = geoPlace(from: doc) else { return nil }
        let snap = GeoSnapshot(placeKey: placeKey, displayPlace: displayPlace,
                               placeName: place.name, country: place.country,
                               latitude: place.lat, longitude: place.lon,
                               fetchedAt: now())
        return snap.isValid ? snap : nil
    }

    private func acquireSlot() async {
        if running < Self.maxConcurrentFetches {
            running += 1
            return
        }
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                waiters.append((id: id, continuation: c))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
        if cancelledWaiters.remove(id) != nil { return }
    }

    private func releaseSlot() {
        if !waiters.isEmpty {
            waiters.removeFirst().continuation.resume()
        } else {
            running -= 1
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let i = waiters.firstIndex(where: { $0.id == id }) else { return }
        let w = waiters.remove(at: i)
        cancelledWaiters.insert(id)
        w.continuation.resume()
    }
}

public extension GeoRefresher {
    /// The app-wide refresher (app-support `locations.json` cache).
    static var shared: GeoRefresher { _shared }
    private static let _shared = GeoRefresher()
}
