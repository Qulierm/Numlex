import Foundation

// MARK: - Transport & errors

/// Injectable network transport: the production default runs
/// `URLSession.shared`; tests inject a mock closure returning canned
/// geocode/forecast payloads per URL, so the suite never needs the
/// internet. Only the explicit place query is ever transmitted — full
/// source documents and arbitrary user text are never logged.
public typealias WeatherTransport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

private func defaultWeatherTransport(_ request: URLRequest) async throws -> (Data, URLResponse) {
    try await URLSession.shared.data(for: request)
}

public enum WeatherServiceError: Error, Equatable, Sendable {
    case badStatus
    case oversize
    case decode
    case noResults
    case invalidPayload
}

// MARK: - Provider documents (Open-Meteo, no API key)

/// Typed decode of the geocoding document
/// (`https://geocoding-api.open-meteo.com/v1/search?name=<place>&
/// count=1&language=en&format=json`). The top-ranked result is used, so
/// ambiguous names resolve deterministically (London → London, United
/// Kingdom). A document with no usable results yields nil from `top`.
public struct WeatherGeocodeDocument: Decodable, Sendable {
    public struct Place: Decodable, Sendable {
        public let name: String
        public let country: String?
        public let admin1: String?
        public let latitude: Double
        public let longitude: Double
    }

    public let results: [Place]?

    /// The deterministic top-ranked place, or nil when the document
    /// carries no usable result (missing/empty results, blank name,
    /// non-finite or out-of-range coordinates).
    public var top: Place? {
        guard let first = results?.first else { return nil }
        guard !first.name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        guard first.latitude.isFinite, first.latitude >= -90, first.latitude <= 90,
              first.longitude.isFinite, first.longitude >= -180, first.longitude <= 180 else {
            return nil
        }
        return first
    }
}

/// Typed decode of the forecast document
/// (`https://api.open-meteo.com/v1/forecast?latitude=…&longitude=…&
/// current=temperature_2m&temperature_unit=celsius&timezone=auto`).
/// Only the current 2m air temperature is consumed; every other field
/// is ignored.
public struct WeatherForecastDocument: Decodable, Sendable {
    public struct Current: Decodable, Sendable {
        public let temperature2m: Double?

        private enum CodingKeys: String, CodingKey {
            case temperature2m = "temperature_2m"
        }
    }

    public struct CurrentUnits: Decodable, Sendable {
        public let temperature2m: String?

        private enum CodingKeys: String, CodingKey {
            case temperature2m = "temperature_2m"
        }
    }

    public let current: Current?
    public let currentUnits: CurrentUnits?

    private enum CodingKeys: String, CodingKey {
        case current
        case currentUnits = "current_units"
    }

    /// The validated Celsius temperature, or nil for any document that
    /// is not a clean Celsius payload: missing `current`/temperature,
    /// non-finite or out-of-range values, or an explicit non-Celsius
    /// unit (the request asks for Celsius, so `°F` means the payload
    /// does not answer this query).
    public var celsiusTemperature: Double? {
        guard let t = current?.temperature2m, t.isFinite,
              t >= WeatherSnapshot.minCelsius, t <= WeatherSnapshot.maxCelsius else {
            return nil
        }
        if let unit = currentUnits?.temperature2m, unit != "°C" { return nil }
        return t
    }
}

// MARK: - Endpoint construction

public enum WeatherEndpoints {
    public static let geocodeHost = "geocoding-api.open-meteo.com"
    public static let forecastHost = "api.open-meteo.com"
    /// Per-request network timeout (seconds).
    public static let timeout: TimeInterval = 10
    /// Response-size cap (bytes): provider documents are small JSON.
    public static let maxResponseBytes = 256 * 1024

    /// `https://geocoding-api.open-meteo.com/v1/search?name=<display>&
    /// count=1&language=en&format=json`, built with URLComponents so
    /// the place is percent-encoded.
    public static func geocodeURL(for displayQuery: String) -> URL? {
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = geocodeHost
        parts.path = "/v1/search"
        parts.queryItems = [
            URLQueryItem(name: "name", value: displayQuery),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json"),
        ]
        return parts.url
    }

    /// `https://api.open-meteo.com/v1/forecast?latitude=…&longitude=…&
    /// current=temperature_2m&temperature_unit=celsius&timezone=auto`.
    public static func forecastURL(latitude: Double, longitude: Double) -> URL? {
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = forecastHost
        parts.path = "/v1/forecast"
        parts.queryItems = [
            URLQueryItem(name: "latitude", value: "\(latitude)"),
            URLQueryItem(name: "longitude", value: "\(longitude)"),
            URLQueryItem(name: "current", value: "temperature_2m"),
            URLQueryItem(name: "temperature_unit", value: "celsius"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        return parts.url
    }

    public static func request(for url: URL) -> URLRequest {
        var r = URLRequest(url: url)
        r.timeoutInterval = timeout
        return r
    }

    /// HTTP 2xx plus the size cap. Non-HTTP responses (used by injected
    /// file/mock transports) skip the status check but keep the cap.
    public static func validatedData(_ data: Data, response: URLResponse) throws -> Data {
        if let http = response as? HTTPURLResponse {
            guard (200..<300).contains(http.statusCode) else {
                throw WeatherServiceError.badStatus
            }
        }
        guard data.count <= maxResponseBytes else {
            throw WeatherServiceError.oversize
        }
        return data
    }
}

// MARK: - Persistent cache

private struct WeatherCacheFile: Codable {
    var entries: [String: WeatherSnapshot] = [:]
}

/// File-backed atomic cache of last-good snapshots by canonical query.
/// Writes go to a sibling temp file renamed over `weather.json`, so
/// readers always see either the old complete cache or the new one.
/// A malformed file loads as empty; invalid entries are dropped on
/// load. Never stores failures — last-good data survives offline.
public struct WeatherStore: Sendable {
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
        fileURL = dir.appendingPathComponent("weather.json")
    }

    /// Sanitized cache: malformed files decode as empty, invalid
    /// snapshots are dropped.
    public func load() -> [String: WeatherSnapshot] {
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(WeatherCacheFile.self, from: data) else {
            return [:]
        }
        return file.entries.filter { $0.value.isValid }
    }

    @discardableResult
    public func save(_ entries: [String: WeatherSnapshot]) -> Bool {
        let clean = entries.filter { $0.value.isValid }
        guard let data = try? JSONEncoder().encode(WeatherCacheFile(entries: clean)) else {
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

/// Per-query current-weather refresher over Open-Meteo (no API key).
/// The in-memory cache seeds from `weather.json` at init; a successful
/// two-step lookup (geocode → forecast) validates and persists the new
/// snapshot. ANY failure keeps serving the last-good snapshot — stale
/// but usable — and a query with no cache at all resolves unavailable
/// upstream. Cancellation never corrupts the cache: a cancelled fetch
/// installs nothing.
public actor WeatherRefresher {
    /// A cached snapshot older than this triggers a background refresh.
    public static let cacheTTL: TimeInterval = 600
    /// Bounded concurrent provider fetches (different cities proceed in
    /// parallel up to this limit; same-query callers share one flight).
    public static let maxConcurrentFetches = 4

    private let store: WeatherStore
    private let transport: WeatherTransport
    private let now: @Sendable () -> Date
    private var cache: [String: WeatherSnapshot]
    private var inFlight: [String: (token: UUID, task: Task<WeatherSnapshot?, Never>)] = [:]
    private var running = 0
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, Never>)] = []
    private var cancelledWaiters: Set<UUID> = []

    public init(store: WeatherStore? = nil,
                transport: WeatherTransport? = nil,
                now: @Sendable @escaping () -> Date = Date.init) {
        let s = store ?? WeatherStore()
        self.store = s
        self.transport = transport ?? defaultWeatherTransport
        self.now = now
        self.cache = s.load()
    }

    /// The last-good snapshot for a query, if any (stale or fresh).
    public func cachedSnapshot(for query: WeatherQuery) -> WeatherSnapshot? {
        let s = cache[query.key]
        return (s != nil && s!.isValid) ? s : nil
    }

    /// True when the query has no cached snapshot or it is older than
    /// the TTL (evaluated against the injected clock).
    public func isStale(_ key: String) -> Bool {
        guard let s = cache[key], s.isValid else { return true }
        return now().timeIntervalSince(s.fetchedAt) > Self.cacheTTL
    }

    /// Fetches and validates the current temperature for a query.
    /// Concurrent callers for the SAME query share one in-flight fetch
    /// (true single-flight); different cities run concurrently up to
    /// `maxConcurrentFetches`. Success installs and persists the new
    /// snapshot; failure returns the stale last-good snapshot (or nil
    /// when the query was never cached) and never overwrites it.
    public func refresh(_ query: WeatherQuery) async -> WeatherSnapshot? {
        if let t = inFlight[query.key]?.task { return await t.value }
        let token = UUID()
        let child = Task<WeatherSnapshot?, Never> {
            await self.fetchAndStore(query)
        }
        inFlight[query.key] = (token: token, task: child)
        defer {
            if inFlight[query.key]?.token == token {
                inFlight.removeValue(forKey: query.key)
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
    public func inject(_ snapshot: WeatherSnapshot) {
        guard snapshot.isValid else { return }
        cache[snapshot.queryKey] = snapshot
        store.save(cache)
    }

    // MARK: Internals

    private func fetchAndStore(_ query: WeatherQuery) async -> WeatherSnapshot? {
        await acquireSlot()
        defer { releaseSlot() }
        // A fetch cancelled before (or during) the network run installs
        // nothing: the caller keeps the pre-fetch last-good value.
        if Task.isCancelled { return cache[query.key] }
        guard let fresh = await fetch(query) else { return cache[query.key] }
        if Task.isCancelled { return cache[query.key] }
        cache[query.key] = fresh
        store.save(cache)
        return fresh
    }

    private func fetch(_ query: WeatherQuery) async -> WeatherSnapshot? {
        guard let geoURL = WeatherEndpoints.geocodeURL(for: query.display) else { return nil }
        guard let (gdata, gresp) = try? await transport(WeatherEndpoints.request(for: geoURL)),
              let gbytes = try? WeatherEndpoints.validatedData(gdata, response: gresp),
              let geo = try? JSONDecoder().decode(WeatherGeocodeDocument.self, from: gbytes),
              let place = geo.top else { return nil }
        guard let fURL = WeatherEndpoints.forecastURL(latitude: place.latitude,
                                                      longitude: place.longitude) else { return nil }
        guard let (fdata, fresp) = try? await transport(WeatherEndpoints.request(for: fURL)),
              let fbytes = try? WeatherEndpoints.validatedData(fdata, response: fresp),
              let forecast = try? JSONDecoder().decode(WeatherForecastDocument.self, from: fbytes),
              let temp = forecast.celsiusTemperature else { return nil }
        let snap = WeatherSnapshot(queryKey: query.key, displayQuery: query.display,
                                   placeName: place.name, country: place.country,
                                   latitude: place.latitude, longitude: place.longitude,
                                   temperatureCelsius: temp, fetchedAt: now())
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
        // Woken by cancellation (never held a slot): hold nothing.
        // A waiter cancelled after a slot transfer instead proceeds —
        // fetchAndStore sees the cancellation and installs nothing.
        if cancelledWaiters.remove(id) != nil { return }
    }

    private func releaseSlot() {
        if !waiters.isEmpty {
            // The slot transfers to the oldest waiter; the count stays.
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

public extension WeatherRefresher {
    /// The app-wide refresher (app-support `weather.json` cache).
    static var shared: WeatherRefresher { _shared }
    private static let _shared = WeatherRefresher()
}
