import Foundation
import NumlexCore

/// r55: natural current-weather queries — `weather in London` shows the
/// current 2m air temperature in Celsius through the existing quantity
/// system (`18.5 C°`, canonical UnitCatalog label).
///
/// Coverage:
/// 1. Strict parser/scanner (exact, case/whitespace, multiword and
///    punctuation places, canonical dedupe + signature, rejections);
/// 2. Open-Meteo documents and endpoint construction (geocode top,
///    no-results, malformed/wrong-unit/missing payloads, URL items +
///    percent-encoding, HTTP/size validation, no secrets);
/// 3. WeatherStore/WeatherRefresher (roundtrip, corrupt load, TTL
///    boundary, stale success/fallback, missing failure, city
///    isolation, single-flight, atomic last-good, cancellation,
///    inject hook) — all with injected mock transports, no internet;
/// 4. Engine integration (ready `C°` number, quiet loading, failure
///    sentinel, env purity, conversion/prose regressions, auto-title,
///    PreviousAnswer, live tokens + token-to-Fahrenheit, Total
///    exclusion, determinism under snapshot change);
/// 5. Copy/menu eligibility of the weather unit result;
/// 6. Source guards (HTTPS only, no GPS, no weather in the persisted
///    payload, weather stage before conversion, localization keys);
/// 7. City syntax amendment: the place span paints ONLY with the
///    existing `.conversion` unit role (exact UTF-16 ranges from the
///    shared parser, multiword/comma/apostrophe/non-ASCII, hyphen
///    never an operator, emoji/surrogate and invalid lines unpainted).

private let WM = "\u{FFFC}"

// MARK: - Local helpers

private func r55Source(_ rel: String) -> String? {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let url = root.appendingPathComponent(rel).standardizedFileURL
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try? String(contentsOf: url, encoding: .utf8)
}

private func r55London(temp: Double = 18.5,
                       fetchedAt: Date = Date()) -> WeatherSnapshot {
    WeatherSnapshot(queryKey: "london", displayQuery: "London",
                    placeName: "London", country: "United Kingdom",
                    latitude: 51.5074, longitude: -0.1278,
                    temperatureCelsius: temp, fetchedAt: fetchedAt)
}

private func r55Context(temp: Double = 18.5) -> WeatherContext {
    WeatherContext(snapshots: ["london": r55London(temp: temp)])
}

private func r55Results(_ content: String,
                        weather: WeatherContext = .empty,
                        decimalPlaces: Int = 2) -> [LineResult] {
    let lines = content.components(separatedBy: "\n")
    return resolveSheet(content: content,
                        lineIDs: lines.map { _ in UUID() },
                        references: [],
                        rates: Rates(),
                        decimalPlaces: decimalPlaces,
                        constants: [],
                        weather: weather).lines.map(\.result)
}

private func r55Resolve(_ content: String,
                        ids: [UUID],
                        refs: [AnswerReference],
                        weather: WeatherContext = .empty)
-> (lines: [SheetLine], tokens: [TokenResolution]) {
    resolveSheet(content: content, lineIDs: ids, references: refs,
                 rates: Rates(), decimalPlaces: 7, weather: weather)
}

// MARK: - Async + mock plumbing (no internet)

private final class R55Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func increment() { lock.lock(); n += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return n }
}

private final class R55Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<T, Error>?
    var done: Result<T, Error>? { lock.lock(); defer { lock.unlock() }; return result }
    func set(_ r: Result<T, Error>) { lock.lock(); result = r; lock.unlock() }
}

private func r55Await<T: Sendable>(
    _ location: String,
    _ op: @escaping @Sendable () async throws -> T
) throws -> T {
    let box = R55Box<T>()
    let sem = DispatchSemaphore(value: 0)
    Task {
        do { box.set(.success(try await op())) }
        catch { box.set(.failure(error)) }
        sem.signal()
    }
    guard sem.wait(timeout: .now() + 30) == .success else {
        throw CaseFailure(message: "operation timed out", location: location)
    }
    guard let r = box.done else {
        throw CaseFailure(message: "no result", location: location)
    }
    return try r.get()
}

private func r55TempStore() throws -> (dir: String, store: WeatherStore) {
    let dir = NSTemporaryDirectory() + "numlex-weather-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    return (dir, WeatherStore(directory: URL(fileURLWithPath: dir)))
}

private func r55HTTP(_ url: URL, status: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
}

private func r55Opaque(_ url: URL) -> URLResponse {
    URLResponse(url: url, mimeType: "application/json",
                expectedContentLength: 100, textEncodingName: "utf-8")
}

private func r55GeocodeJSON(name: String = "London",
                            country: String? = "United Kingdom",
                            lat: Double = 51.5074,
                            lon: Double = -0.1278) -> Data {
    let c = country.map { "\"country\": \"\($0)\"," } ?? ""
    return """
    {"results": [{"name": "\(name)", \(c) "admin1": "England",
     "latitude": \(lat), "longitude": \(lon)}]}
    """.data(using: .utf8)!
}

private func r55ForecastJSON(temp: String?, units: String? = "\"°C\"") -> Data {
    let t = temp.map { "\"temperature_2m\": \($0)" } ?? ""
    let u = units.map { "\"current_units\": {\"temperature_2m\": \($0)}," } ?? ""
    return """
    {\(u) "current": {\(t)}}
    """.data(using: .utf8)!
}

private func r55Router(geocode: Data, forecast: Data,
                       counter: R55Counter? = nil,
                       delayMs: Int64 = 0) -> WeatherTransport {
    { request in
        counter?.increment()
        if delayMs > 0 { try? await Task.sleep(for: .milliseconds(delayMs)) }
        let url = request.url!
        let payload = url.host == WeatherEndpoints.geocodeHost ? geocode : forecast
        return (payload, r55HTTP(url, status: 200))
    }
}

private let r55LondonQuery = WeatherQuery.parse("weather in London")!

public let r55Cases: [EngineCase] = [
    // MARK: 1. Strict parser

    EngineCase("r55-parse-exact-london") {
        let q = WeatherQuery.parse("weather in London")
        try expectEqual(q?.key, "london", "canonical key")
        try expectEqual(q?.display, "London", "display keeps case")
    },

    EngineCase("r55-parse-case-and-space-flexible") {
        try expectEqual(WeatherQuery.parse("WEATHER IN London")?.key, "london", "upper keyword")
        try expectEqual(WeatherQuery.parse("Weather  In  Paris")?.key, "paris", "flexible spaces")
        try expectEqual(WeatherQuery.parse("  weather in London  ")?.display, "London", "edges trimmed")
        try expectEqual(WeatherQuery.parse("weather\tin\tLondon")?.key, "london", "tabs split")
    },

    EngineCase("r55-parse-places") {
        try expectEqual(WeatherQuery.parse("weather in New York")?.key, "new york", "multiword")
        try expectEqual(WeatherQuery.parse("weather in Paris, France")?.display,
                        "Paris, France", "comma disambiguation")
        try expectEqual(WeatherQuery.parse("weather in St. Louis")?.key, "st. louis", "period")
        try expectEqual(WeatherQuery.parse("weather in Aix-en-Provence")?.key,
                        "aix-en-provence", "hyphen")
        try expectEqual(WeatherQuery.parse("weather in São Paulo")?.key, "são paulo", "non-ASCII")
        try expectEqual(WeatherQuery.parse("weather in 北京")?.key, "北京", "CJK")
        try expectEqual(WeatherQuery.parse("weather in Côte d’Ivoire")?.display,
                        "Côte d’Ivoire", "apostrophe")
    },

    EngineCase("r55-parse-rejects-empty-and-bounds") {
        try expect(WeatherQuery.parse("weather in") == nil, "missing place", "empty")
        try expect(WeatherQuery.parse("weather in   ") == nil, "blank place", "blank")
        try expect(WeatherQuery.parse("weather") == nil, "bare keyword", "bare")
        try expect(WeatherQuery.parse("weather today") == nil, "no in-keyword", "no-in")
        try expect(WeatherQuery.parse("weather inside London") == nil, "inside != in", "prefix")
        try expect(WeatherQuery.parse("weather in,,,") == nil, "punctuation only", "punct")
        let ok = String(repeating: "a", count: 100)
        try expect(WeatherQuery.parse("weather in \(ok)")?.key == ok, "100 chars fit", "max")
        try expect(WeatherQuery.parse("weather in \(ok)x") == nil, "101 chars rejected", "over")
        try expect(WeatherQuery.parse("weather in Lon\u{0007}don") == nil, "control char", "ctl")
    },

    EngineCase("r55-parse-rejects-operators-and-syntax") {
        try expect(WeatherQuery.parse("weather in London + 5") == nil, "trailing plus", "+")
        try expect(WeatherQuery.parse("weather in London - 5") == nil, "spaced minus", "-")
        try expect(WeatherQuery.parse("weather in A/B") == nil, "slash", "/")
        try expect(WeatherQuery.parse("weather in X=Y") == nil, "equals", "=")
        try expect(WeatherQuery.parse("weather in (London)") == nil, "parens", "()")
        try expect(WeatherQuery.parse("weather in 50%") == nil, "percent", "%")
        try expect(WeatherQuery.parse("weather in London!") == nil, "bang", "!")
        try expect(WeatherQuery.parse("weather in London" + WM) == nil, "token marker", "marker")
        try expect(WeatherQuery.parse("2 + weather in London") == nil, "leading expr", "lead")
    },

    EngineCase("r55-scan-dedupe-and-skip") {
        let qs = WeatherQuery.scanQueries(in:
            "weather in Paris\nweather in London\nweather in  paris\n# weather in Rome\n// weather in Oslo\nthe weather in London is nice\nweather today\nweather in London + 5\n")
        try expectEqual(qs.map(\.key), ["paris", "london"], "unique first-seen order")
        try expect(WeatherQuery.scanQueries(in: "").isEmpty, "empty content", "empty")
    },

    EngineCase("r55-signature-stable") {
        let a = [WeatherQuery.parse("weather in Paris")!, WeatherQuery.parse("weather in London")!]
        let b = [WeatherQuery.parse("weather in London")!, WeatherQuery.parse("weather in paris")!]
        try expectEqual(WeatherQuery.signature(for: a), WeatherQuery.signature(for: b),
                        "order- and case-insensitive")
        let c = a + [WeatherQuery.parse("weather in Rome")!]
        try expect(WeatherQuery.signature(for: c) != WeatherQuery.signature(for: a),
                   "query change alters signature", "change")
    },

    // MARK: 2. Provider documents and endpoints

    EngineCase("r55-geocode-top-result") {
        let doc = try JSONDecoder().decode(WeatherGeocodeDocument.self,
                                           from: r55GeocodeJSON())
        try expectEqual(doc.top?.name, "London", "top name")
        try expectEqual(doc.top?.country, "United Kingdom", "country")
        try expectClose(doc.top?.latitude ?? -1, 51.5074, 1e-9, "lat")
        try expectClose(doc.top?.longitude ?? -1, -0.1278, 1e-9, "lon")
    },

    EngineCase("r55-geocode-no-results") {
        for payload in ["{}", "{\"results\": []}",
                        "{\"results\": [{\"name\": \"\", \"latitude\": 0, \"longitude\": 0}]}",
                        "{\"results\": [{\"name\": \"X\", \"latitude\": 120, \"longitude\": 0}]}"] {
            let doc = try JSONDecoder().decode(WeatherGeocodeDocument.self,
                                               from: payload.data(using: .utf8)!)
            try expect(doc.top == nil, "no usable top: \(payload)", "nil")
        }
    },

    EngineCase("r55-forecast-celsius-ok") {
        let doc = try JSONDecoder().decode(WeatherForecastDocument.self,
                                           from: r55ForecastJSON(temp: "18.5"))
        try expectClose(doc.celsiusTemperature ?? -999, 18.5, 1e-9, "temperature")
    },

    EngineCase("r55-forecast-rejects-bad-payloads") {
        // Wrong units, missing current/temperature, out-of-range values.
        for payload in [r55ForecastJSON(temp: "18.5", units: "\"°F\""),
                        r55ForecastJSON(temp: nil),
                        "{\"current_units\": {\"temperature_2m\": \"°C\"}}".data(using: .utf8)!,
                        r55ForecastJSON(temp: "80"),
                        r55ForecastJSON(temp: "-120")] {
            let doc = try JSONDecoder().decode(WeatherForecastDocument.self, from: payload)
            try expect(doc.celsiusTemperature == nil, "rejected: \(String(data: payload, encoding: .utf8) ?? "?")", "nil")
        }
        // Missing units block is accepted: the request asked for Celsius.
        let bare = try JSONDecoder().decode(WeatherForecastDocument.self,
                                            from: r55ForecastJSON(temp: "7", units: nil))
        try expectClose(bare.celsiusTemperature ?? -999, 7, 1e-9, "units block optional")
    },

    EngineCase("r55-endpoint-geocode-url") {
        guard let url = WeatherEndpoints.geocodeURL(for: "New York") else {
            throw CaseFailure(message: "geocode URL must build", location: "R55Cases")
        }
        try expectEqual(url.scheme, "https", "https only")
        try expectEqual(url.host, "geocoding-api.open-meteo.com", "geocode host")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func val(_ n: String) -> String? { items.first(where: { $0.name == n })?.value }
        try expectEqual(val("name"), "New York", "place item")
        try expectEqual(val("count"), "1", "single result")
        try expectEqual(val("language"), "en", "english")
        try expectEqual(val("format"), "json", "json")
        try expect(url.absoluteString.contains("New%20York"), "percent-encoded", "enc")
        try expect(!url.absoluteString.contains(" "), "no raw spaces", "raw")
    },

    EngineCase("r55-endpoint-forecast-url") {
        guard let url = WeatherEndpoints.forecastURL(latitude: 51.5074, longitude: -0.1278) else {
            throw CaseFailure(message: "forecast URL must build", location: "R55Cases")
        }
        try expectEqual(url.scheme, "https", "https only")
        try expectEqual(url.host, "api.open-meteo.com", "forecast host")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func val(_ n: String) -> String? { items.first(where: { $0.name == n })?.value }
        try expectEqual(val("latitude"), "51.5074", "lat item")
        try expectEqual(val("longitude"), "-0.1278", "lon item")
        try expectEqual(val("current"), "temperature_2m", "current field")
        try expectEqual(val("temperature_unit"), "celsius", "celsius requested")
        try expectEqual(val("timezone"), "auto", "timezone")
        try expectEqual(WeatherEndpoints.request(for: url).timeoutInterval, 10, "timeout")
    },

    EngineCase("r55-response-validation") {
        let url = URL(string: "https://api.open-meteo.com/v1/forecast")!
        let small = Data(repeating: 0, count: 100)
        try expectEqual(try WeatherEndpoints.validatedData(small, response: r55HTTP(url, status: 200)).count,
                        100, "2xx passes")
        do {
            _ = try WeatherEndpoints.validatedData(small, response: r55HTTP(url, status: 500))
            throw CaseFailure(message: "non-2xx must throw", location: "R55Cases")
        } catch WeatherServiceError.badStatus { /* expected */ }
        do {
            let big = Data(repeating: 0, count: WeatherEndpoints.maxResponseBytes + 1)
            _ = try WeatherEndpoints.validatedData(big, response: r55HTTP(url, status: 200))
            throw CaseFailure(message: "oversize must throw", location: "R55Cases")
        } catch WeatherServiceError.oversize { /* expected */ }
        // Non-HTTP (injected/file) responses skip the status check.
        try expectEqual(try WeatherEndpoints.validatedData(small, response: r55Opaque(url)).count,
                        100, "opaque passes")
    },

    // MARK: 3. Store and refresher

    EngineCase("r55-store-roundtrip") {
        let (dir, store) = try r55TempStore()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let snap = r55London(temp: 18.5)
        try expect(store.save(["london": snap]), "save succeeds", "save")
        guard let back = store.load()["london"] else {
            throw CaseFailure(message: "saved snapshot must load", location: "R55Cases")
        }
        try expectEqual(back, snap, "roundtrip equal")
    },

    EngineCase("r55-store-corrupt-and-invalid") {
        let (dir, store) = try r55TempStore()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try expect(store.load().isEmpty, "missing file", "missing")
        try "not json".write(toFile: dir + "/weather.json", atomically: true, encoding: .utf8)
        try expect(store.load().isEmpty, "corrupt file loads empty", "corrupt")
        // Invalid entries are dropped, valid ones survive.
        let bad = WeatherSnapshot(queryKey: "bad", displayQuery: "Bad", placeName: "Bad",
                                  country: nil, latitude: 0, longitude: 0,
                                  temperatureCelsius: 500, fetchedAt: Date())
        try expect(!bad.isValid, "500 C is invalid", "guard")
        try expect(store.save(["bad": bad, "london": r55London()]), "mixed save", "save")
        let loaded = store.load()
        try expect(loaded["bad"] == nil, "invalid dropped", "drop")
        try expect(loaded["london"] != nil, "valid kept", "keep")
    },

    EngineCase("r55-refresh-success-installs") {
        let (dir, store) = try r55TempStore()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let refresher = WeatherRefresher(
            store: store,
            transport: r55Router(geocode: r55GeocodeJSON(), forecast: r55ForecastJSON(temp: "18.5")))
        let snap = try r55Await("refresh-success") { await refresher.refresh(r55LondonQuery) }
        try expectClose(snap?.temperatureCelsius ?? -999, 18.5, 1e-9, "temperature")
        try expectEqual(snap?.queryKey, "london", "key")
        try expectEqual(snap?.placeName, "London", "place")
        try expect(snap?.isValid == true, "valid snapshot", "valid")
        try expect(store.load()["london"] == snap, "persisted", "persist")
        let stale = try r55Await("refresh-fresh") { await refresher.isStale("london") }
        try expect(!stale, "fresh after success", "fresh")
    },

    EngineCase("r55-refresh-missing-failure-is-nil") {
        let (dir, store) = try r55TempStore()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let failing: WeatherTransport = { _ in throw URLError(.notConnectedToInternet) }
        let refresher = WeatherRefresher(store: store, transport: failing)
        let snap = try r55Await("refresh-fail") { await refresher.refresh(r55LondonQuery) }
        try expect(snap == nil, "no cache + failure = nil", "nil")
        try expect(store.load().isEmpty, "failure persists nothing", "empty")
    },

    EngineCase("r55-refresh-stale-fallback-keeps-last-good") {
        let (dir, store) = try r55TempStore()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let old = r55London(temp: 18.5,
                            fetchedAt: Date().addingTimeInterval(-3_600))
        try expect(store.save(["london": old]), "seed stale cache", "seed")
        let before = try Data(contentsOf: store.fileURL)
        let failing: WeatherTransport = { _ in throw URLError(.timedOut) }
        let refresher = WeatherRefresher(store: store, transport: failing)
        let snap = try r55Await("stale-fallback") { await refresher.refresh(r55LondonQuery) }
        try expectEqual(snap, old, "stale last-good wins over failure")
        try expectEqual(try Data(contentsOf: store.fileURL), before, "cache file untouched")
    },

    EngineCase("r55-refresh-stale-success-replaces") {
        let (dir, store) = try r55TempStore()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let old = r55London(temp: 18.5,
                            fetchedAt: Date().addingTimeInterval(-3_600))
        try expect(store.save(["london": old]), "seed stale cache", "seed")
        let refresher = WeatherRefresher(
            store: store,
            transport: r55Router(geocode: r55GeocodeJSON(), forecast: r55ForecastJSON(temp: "21")))
        let snap = try r55Await("stale-success") { await refresher.refresh(r55LondonQuery) }
        try expectClose(snap?.temperatureCelsius ?? -999, 21, 1e-9, "fresh value")
        try expectClose(store.load()["london"]?.temperatureCelsius ?? -999, 21, 1e-9, "persisted")
    },

    EngineCase("r55-ttl-boundary") {
        let (dir, store) = try r55TempStore()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let base = Date()
        let clockNow = R55ClockBox(base)
        let refresher = WeatherRefresher(store: store, transport: nil,
                                         now: { clockNow.get() })
        try r55Await("ttl-inject") {
            await refresher.inject(r55London(temp: 10, fetchedAt: base))
        }
        clockNow.set(base.addingTimeInterval(WeatherRefresher.cacheTTL))
        let edge = try r55Await("ttl-edge") { await refresher.isStale("london") }
        try expect(!edge, "exactly TTL is fresh", "edge")
        clockNow.set(base.addingTimeInterval(WeatherRefresher.cacheTTL + 1))
        let over = try r55Await("ttl-over") { await refresher.isStale("london") }
        try expect(over, "past TTL is stale", "over")
        let missing = try r55Await("ttl-missing") { await refresher.isStale("rome") }
        try expect(missing, "missing is stale", "missing")
    },

    EngineCase("r55-cities-isolated") {
        let (dir, store) = try r55TempStore()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let transport: WeatherTransport = { request in
            let url = request.url!
            if url.host == WeatherEndpoints.geocodeHost {
                let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "name" })?.value ?? ""
                if q == "Paris" {
                    return (r55GeocodeJSON(name: "Paris", country: "France",
                                           lat: 48.8566, lon: 2.3522),
                            r55HTTP(url, status: 200))
                }
                return (r55GeocodeJSON(), r55HTTP(url, status: 200))
            }
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func val(_ n: String) -> String { comps.first(where: { $0.name == n })?.value ?? "" }
            let temp = val("latitude").hasPrefix("48.85") ? "21" : "18.5"
            return (r55ForecastJSON(temp: temp), r55HTTP(url, status: 200))
        }
        let refresher = WeatherRefresher(store: store, transport: transport)
        let paris = WeatherQuery.parse("weather in Paris")!
        let (l, p) = try r55Await("cities") {
            async let a = refresher.refresh(r55LondonQuery)
            async let b = refresher.refresh(paris)
            return await (a, b)
        }
        try expectClose(l?.temperatureCelsius ?? -999, 18.5, 1e-9, "london temp")
        try expectClose(p?.temperatureCelsius ?? -999, 21, 1e-9, "paris temp")
        try expectEqual(p?.placeName, "Paris", "paris place")
        let cached = try r55Await("cities-cache") {
            await refresher.cachedSnapshot(for: paris)
        }
        try expect(cached == p, "both cached", "cache")
    },

    EngineCase("r55-single-flight-shares-one-lookup") {
        let (dir, store) = try r55TempStore()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let counter = R55Counter()
        let refresher = WeatherRefresher(
            store: store,
            transport: r55Router(geocode: r55GeocodeJSON(),
                                 forecast: r55ForecastJSON(temp: "18.5"),
                                 counter: counter, delayMs: 60))
        let results = try r55Await("single-flight") {
            await withTaskGroup(of: WeatherSnapshot?.self) { group in
                for _ in 0..<5 { group.addTask { await refresher.refresh(r55LondonQuery) } }
                var out: [WeatherSnapshot?] = []
                for await r in group { out.append(r) }
                return out
            }
        }
        try expectEqual(results.count, 5, "all callers answered")
        for r in results {
            try expectClose(r?.temperatureCelsius ?? -999, 18.5, 1e-9, "same result")
        }
        // One shared flight = exactly one geocode + one forecast fetch.
        try expectEqual(counter.count, 2, "single flight")
    },

    EngineCase("r55-cancel-installs-nothing") {
        let (dir, store) = try r55TempStore()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let refresher = WeatherRefresher(
            store: store,
            transport: r55Router(geocode: r55GeocodeJSON(),
                                 forecast: r55ForecastJSON(temp: "18.5"),
                                 delayMs: 400))
        let got = try r55Await("cancel") {
            let t = Task { await refresher.refresh(r55LondonQuery) }
            try? await Task.sleep(for: .milliseconds(50))
            t.cancel()
            return await t.value
        }
        try expect(got == nil, "cancelled fetch yields no snapshot", "nil")
        try expect(store.load().isEmpty, "cancelled fetch persists nothing", "empty")
    },

    EngineCase("r55-inject-installs-without-network") {
        let (dir, store) = try r55TempStore()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let counter = R55Counter()
        let refresher = WeatherRefresher(
            store: store,
            transport: r55Router(geocode: r55GeocodeJSON(),
                                 forecast: r55ForecastJSON(temp: "0"),
                                 counter: counter))
        try r55Await("inject") { await refresher.inject(r55London(temp: 12)) }
        try expectEqual(counter.count, 0, "no network for inject")
        let back = try r55Await("inject-read") {
            await refresher.cachedSnapshot(for: r55LondonQuery)
        }
        try expectClose(back?.temperatureCelsius ?? -999, 12, 1e-9, "installed")
        try expect(store.load()["london"] == back, "inject persists")
        // Invalid snapshots are refused and change nothing.
        let bad = WeatherSnapshot(queryKey: "london", displayQuery: "London", placeName: "London",
                                  country: nil, latitude: 0, longitude: 0,
                                  temperatureCelsius: 500, fetchedAt: Date())
        try r55Await("inject-bad") { await refresher.inject(bad) }
        let kept = try r55Await("inject-kept") {
            await refresher.cachedSnapshot(for: r55LondonQuery)
        }
        try expectEqual(kept, back, "invalid inject refused")
    },

    EngineCase("r55-garbage-payload-is-nil") {
        let (dir, store) = try r55TempStore()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let transport: WeatherTransport = { request in
            (Data("not json".utf8), r55HTTP(request.url!, status: 200))
        }
        let refresher = WeatherRefresher(store: store, transport: transport)
        let snap = try r55Await("garbage") { await refresher.refresh(r55LondonQuery) }
        try expect(snap == nil, "undecodable payload yields nil", "nil")
    },

    // MARK: 4. Engine integration

    EngineCase("r55-ready-is-celsius-number") {
        let r = r55Results("weather in London", weather: r55Context())
        try expectEqual(r.count, 1, "one result per line")
        try expectEqual(r[0], .number(value: 18.5, unit: "C°"), "ready temperature")
    },

    EngineCase("r55-loading-stays-quiet") {
        let r = r55Results("weather in London")
        try expectEqual(r[0], .skip, "empty context renders like prose")
        let pending = WeatherContext(pendingKeys: ["london"])
        try expectEqual(r55Results("weather in London", weather: pending)[0],
                        .skip, "pending stays quiet")
    },

    EngineCase("r55-failure-sentinel") {
        let failed = WeatherContext(failedKeys: ["london"])
        let r = r55Results("weather in London", weather: failed)
        try expectEqual(r[0], .error(message: "Weather unavailable"), "sentinel")
        try expect(WeatherQuery.isUnavailableMessage("Weather unavailable"), "helper true", "t")
        try expect(!WeatherQuery.isUnavailableMessage("Rates unavailable"), "helper false", "f")
    },

    EngineCase("r55-stale-snapshot-wins-over-failure") {
        let both = WeatherContext(snapshots: ["london": r55London(temp: 17)],
                                  failedKeys: ["london"])
        try expectEqual(r55Results("weather in London", weather: both)[0],
                        .number(value: 17, unit: "C°"), "last-good wins")
    },

    EngineCase("r55-canonical-key-is-case-insensitive") {
        try expectEqual(r55Results("Weather In LONDON", weather: r55Context())[0],
                        .number(value: 18.5, unit: "C°"), "display varies, key matches")
    },

    EngineCase("r55-no-env-mutation") {
        let r = r55Results("x = 5\nweather in London\nx × 2")
        try expectEqual(r[0], .variable(name: "x", value: 5), "assignment")
        try expectEqual(r[1], .skip, "loading weather")
        try expectEqual(r[2], .number(value: 10, unit: nil), "env intact below")
    },

    EngineCase("r55-declared-weather-name-keeps-working") {
        let r = r55Results("weather = 5\nweather + 1")
        try expectEqual(r[0], .variable(name: "weather", value: 5), "assignment")
        try expectEqual(r[1], .number(value: 6, unit: nil), "plain reference")
    },

    EngineCase("r55-conversion-and-prose-unaffected") {
        let r = r55Results("100 C to F\nthe weather in London is nice\nweather today")
        try expectEqual(r[0], .number(value: 212, unit: "F°"), "affine conversion")
        try expectEqual(r[1], .skip, "prose stays prose")
        try expectEqual(r[2], .skip, "incomplete query stays quiet")
    },

    EngineCase("r55-celsius-label-converts") {
        try expectEqual(WeatherQuery.celsiusUnitLabel, "C°", "canonical label")
        try expect(UnitCatalog.resolveLabel("C°") != nil, "label resolves", "resolve")
        let r = r55Results("18 C° to F°")
        try expectEqual(r[0], .number(value: 64.4, unit: "F°"), "degree label converts")
    },

    EngineCase("r55-auto-title-recognizes-query") {
        try expectEqual(Sheet.autoTitle(from: "weather in London", fallback: "Sheet"),
                        "weather in London", "titles before network")
        try expectEqual(Sheet.autoTitle(from: "notes\nweather in London", fallback: "Sheet"),
                        "weather in London", "skips prose first")
    },

    EngineCase("r55-previous-answer-uses-ready-weather") {
        let content = "weather in London\n"
        let ids = [UUID(), UUID()]
        let caret = (content as NSString).length
        let hit = PreviousAnswerPlan.plan(content: content, lineIDs: ids, caret: caret,
                                          op: "+", weather: r55Context())
        try expectEqual(hit?.sourceLineIndex, 0, "ready weather is answerable")
        let miss = PreviousAnswerPlan.plan(content: content, lineIDs: ids, caret: caret, op: "+")
        try expect(miss == nil, "loading weather never qualifies", "quiet")
    },

    EngineCase("r55-token-shows-live-temperature") {
        let u0 = UUID(), u1 = UUID()
        let content = "weather in London\n" + WM
        let (lines, tokens) = r55Resolve(content, ids: [u0, u1],
                                         refs: [AnswerReference(sourceLineID: u0, labelLine: 1,
                                                                location: 18)],
                                         weather: r55Context())
        try expectEqual(lines[1].result, .number(value: 18.5, unit: "C°"), "bare token quantity")
        try expectEqual(tokens[0].state,
                        .active(value: 18.5, unit: "C°", display: "18.5 C°"), "live state")
        // The token stays live when the snapshot updates.
        let (lines2, _) = r55Resolve(content, ids: [u0, u1],
                                     refs: [AnswerReference(sourceLineID: u0, labelLine: 1,
                                                            location: 18)],
                                     weather: r55Context(temp: 20))
        try expectEqual(lines2[1].result, .number(value: 20, unit: "C°"), "updated snapshot")
    },

    EngineCase("r55-token-converts-to-fahrenheit") {
        let u0 = UUID(), u1 = UUID()
        let (lines, _) = r55Resolve("weather in London\n" + WM + " to fahrenheit",
                                    ids: [u0, u1],
                                    refs: [AnswerReference(sourceLineID: u0, labelLine: 1,
                                                           location: 18)],
                                    weather: r55Context())
        if case .number(let v, let u) = lines[1].result {
            try expectClose(v, 65.3, 1e-9, "18.5 C in F")
            try expectEqual(u, "F°", "fahrenheit label")
        } else {
            throw CaseFailure(message: "token must convert, got \(lines[1].result)",
                              location: "R55Cases")
        }
    },

    EngineCase("r55-weather-excluded-from-total") {
        // The summary bar sums only unitless numbers; a unit-bearing
        // weather result is structurally excluded.
        if case .number(_, let u) = r55Results("weather in London",
                                               weather: r55Context())[0] {
            try expect(u != nil, "weather carries its unit", "unit")
            try expectEqual(u, "C°", "celsius label")
        } else {
            throw CaseFailure(message: "ready weather must be a number",
                              location: "R55Cases")
        }
    },

    EngineCase("r55-deterministic-under-snapshot-change") {
        let content = "weather in London\n1 + 1"
        let ids = [UUID(), UUID()]
        func run(_ temp: Double) -> [SheetLine] {
            r55Resolve(content, ids: ids, refs: [],
                       weather: r55Context(temp: temp)).lines
        }
        let a = run(18.5), b = run(20)
        try expectEqual(a.count, b.count, "same line count")
        try expectEqual(a.map(\.sourceLineIndex), b.map(\.sourceLineIndex), "same mapping")
        try expectEqual(b[1].result, .number(value: 2, unit: nil), "neighbors stable")
        try expect(a[0].result != b[0].result, "only the reading changes", "value")
    },

    EngineCase("r55-duplicate-lines-one-lookup") {
        let qs = WeatherQuery.scanQueries(in: "weather in London\n1 + 1\nweather in London")
        try expectEqual(qs.count, 1, "duplicates share one lookup")
        let r = r55Results("weather in London\n1 + 1\nweather in London",
                           weather: r55Context())
        try expectEqual(r[0], r[2], "both lines read the same snapshot")
    },

    // MARK: 5. Copy and menu eligibility

    EngineCase("r55-weather-copy-and-menu") {
        let row = LineResult.number(value: 18.5, unit: "C°")
        try expectEqual(AnswerDisplay.text(for: row, decimalPlaces: 1),
                        "18.5 C°", "copy matches display")
        let menu = AnswerDisplay.menu(for: row)
        try expectEqual(menu?.showsActions, true, "copy offered")
        try expectEqual(menu?.showsRounding, true, "slider eligible")
        let bad = LineResult.error(message: "Weather unavailable")
        try expectEqual(AnswerDisplay.text(for: bad, decimalPlaces: 2), nil, "no copy")
        try expectEqual(AnswerDisplay.menu(for: bad), nil, "no menu")
    },

    // MARK: 6. Source guards

    EngineCase("r55-source-https-only") {
        guard let svc = r55Source("Sources/NumlexCore/Services/WeatherService.swift") else {
            throw CaseFailure(message: "service source must exist", location: "R55Cases")
        }
        try expect(!svc.contains("\"http://"), "no plaintext URLs", "https")
        try expect(svc.contains("geocoding-api.open-meteo.com"), "geocode host", "geo")
        try expect(svc.contains("api.open-meteo.com"), "forecast host", "fc")
        try expect(!svc.contains("api_key") && !svc.contains("apikey"),
                   "no API secrets", "secrets")
    },

    EngineCase("r55-source-no-location-tracking") {
        for rel in ["Sources/NumlexCore/Services/WeatherService.swift",
                    "Sources/NumlexCore/Engine/WeatherQuery.swift",
                    "Sources/NumlexApp/AppModel.swift"] {
            guard let src = r55Source(rel) else {
                throw CaseFailure(message: "missing \(rel)", location: "R55Cases")
            }
            try expect(!src.contains("CoreLocation"), "no GPS in \(rel)", "gps")
            try expect(!src.contains("CLLocation"), "no location in \(rel)", "loc")
        }
    },

    EngineCase("r55-source-weather-out-of-payload") {
        guard let persist = r55Source("Sources/NumlexCore/Services/Persistence.swift") else {
            throw CaseFailure(message: "persistence source must exist", location: "R55Cases")
        }
        try expect(!persist.contains("eather"), "no weather in Persistence", "persist")
        try expect(persist.contains("currentVersion = 2"), "store version unbumped", "v2")
        guard let sheet = r55Source("Sources/NumlexCore/Models/Sheet.swift") else {
            throw CaseFailure(message: "sheet source must exist", location: "R55Cases")
        }
        for token in ["weather.json", "WeatherSnapshot", "WeatherStore", "WeatherRefresher",
                      "weatherSnapshots"] {
            try expect(!sheet.contains(token), "Sheet holds no \(token)", "sheet")
        }
    },

    EngineCase("r55-source-weather-before-conversion") {
        guard let eval = r55Source("Sources/NumlexCore/Engine/Evaluator.swift") else {
            throw CaseFailure(message: "evaluator source must exist", location: "R55Cases")
        }
        guard let w = eval.range(of: "WeatherQuery.parse(line)"),
              let c = eval.range(of: "tryConversion(line") else {
            throw CaseFailure(message: "both stages must exist", location: "R55Cases")
        }
        try expect(w.lowerBound < c.lowerBound, "weather stage runs first", "order")
    },

    // MARK: 7. City syntax (amendment: place span uses `.conversion`)

    EngineCase("r55-syntax-city-exact-range") {
        // ONLY the city carries the unit role; `in` is a specifier,
        // `weather` stays base text.
        let s = SyntaxClassifier.spans(for: "weather in London",
                                       rates: Rates(), decimalPlaces: 7)[0]
        try expectEqual(s.filter { $0.role == .conversion }.map { $0.range },
                        [NSRange(location: 11, length: 6)], "city is the unit span")
        try expectEqual(s.filter { $0.role == .specifier }.map { $0.range },
                        [NSRange(location: 8, length: 2)], "`in` is a specifier")
        try expect(s.filter { $0.role == .variable }.isEmpty, "no variable paint")
        try expect(s.filter { $0.role == .number }.isEmpty, "no number paint")
        // The shared parser is the single source of truth for the span.
        try expectEqual(WeatherQuery.placeRange(in: "weather in London"),
                        NSRange(location: 11, length: 6), "range from parser")
    },

    EngineCase("r55-syntax-city-whitespace") {
        // Leading/trailing whitespace is excluded; inner runs included.
        let lead = SyntaxClassifier.spans(for: "  weather in London  ",
                                          rates: Rates(), decimalPlaces: 7)[0]
        try expectEqual(lead.filter { $0.role == .conversion }.map { $0.range },
                        [NSRange(location: 13, length: 6)], "edges trimmed")
        let inner = SyntaxClassifier.spans(for: "weather in  New   York",
                                           rates: Rates(), decimalPlaces: 7)[0]
        try expectEqual(inner.filter { $0.role == .conversion }.map { $0.range },
                        [NSRange(location: 12, length: 10)], "inner spaces inside")
        let tabs = SyntaxClassifier.spans(for: "weather\tin\tTokyo",
                                          rates: Rates(), decimalPlaces: 7)[0]
        try expectEqual(tabs.filter { $0.role == .conversion }.map { $0.range },
                        [NSRange(location: 11, length: 5)], "tab separators")
        try expectEqual(WeatherQuery.placeRange(in: "WEATHER IN Paris"),
                        NSRange(location: 11, length: 5), "case-insensitive range")
    },

    EngineCase("r55-syntax-city-multiword-punctuation") {
        // Full meaningful place: multiword, comma, period, apostrophe.
        let cases: [(String, NSRange)] = [
            ("weather in New York", NSRange(location: 11, length: 8)),
            ("weather in Paris, France", NSRange(location: 11, length: 13)),
            ("weather in St. Louis", NSRange(location: 11, length: 9)),
            ("weather in C\u{00F4}te d'Ivoire", NSRange(location: 11, length: 13)),
            ("weather in C\u{00F4}te d\u{2019}Ivoire", NSRange(location: 11, length: 13)),
        ]
        for (line, want) in cases {
            let s = SyntaxClassifier.spans(for: line, rates: Rates(), decimalPlaces: 7)[0]
            try expectEqual(s.filter { $0.role == .conversion }.map { $0.range },
                            [want], "unit span for \(line)")
        }
    },

    EngineCase("r55-syntax-city-non-ascii") {
        // Non-ASCII letters share the unit paint with exact UTF-16 ranges.
        let umlaut = SyntaxClassifier.spans(for: "weather in M\u{00FC}nchen",
                                            rates: Rates(), decimalPlaces: 7)[0]
        try expectEqual(umlaut.filter { $0.role == .conversion }.map { $0.range },
                        [NSRange(location: 11, length: 7)], "latin-1 range")
        let cjk = SyntaxClassifier.spans(for: "weather in \u{5317}\u{4EAC}",
                                         rates: Rates(), decimalPlaces: 7)[0]
        try expectEqual(cjk.filter { $0.role == .conversion }.map { $0.range },
                        [NSRange(location: 11, length: 2)], "CJK range")
    },

    EngineCase("r55-syntax-city-hyphen-stays-unit") {
        // A glued hyphen is a name: the whole city stays ONE conversion
        // span, never split by an operator color.
        let s = SyntaxClassifier.spans(for: "weather in Aix-en-Provence",
                                       rates: Rates(), decimalPlaces: 7)[0]
        try expectEqual(s.filter { $0.role == .conversion }.map { $0.range },
                        [NSRange(location: 11, length: 15)], "hyphenated city whole")
        try expect(s.filter { $0.role == .operatorGlyph }.isEmpty,
                   "hyphen never an operator", "hyphen")
    },

    EngineCase("r55-syntax-emoji-surrogate-rejection") {
        // Emoji/symbols are rejected: no unit paint anywhere on the line.
        for line in ["weather in London\u{1F600}",
                     "weather in Tokyo\u{1F6A9}",
                     "weather in London + 5",
                     "weather in London - 5",
                     "weather in Paris = 3"] {
            try expect(WeatherQuery.parse(line) == nil, "rejected: \(line)", "parse")
            try expect(WeatherQuery.placeRange(in: line) == nil, "no range", "range")
            let s = SyntaxClassifier.spans(for: line, rates: Rates(), decimalPlaces: 7)[0]
            try expect(s.filter { $0.role == .conversion }.isEmpty,
                       "no unit paint: \(line)", "paint")
        }
    },

    EngineCase("r55-syntax-invalid-lines-unpainted") {
        // Invalid/incomplete/prose/comment/token lines never paint
        // arbitrary tails as units.
        for line in ["weather in",
                     "weather in   ",
                     "weather",
                     "weather today",
                     "the weather in London is nice",
                     "London is nice"] {
            let s = SyntaxClassifier.spans(for: line, rates: Rates(), decimalPlaces: 7)[0]
            try expect(s.filter { $0.role == .conversion }.isEmpty,
                       "no unit paint: '\(line)'", "paint")
        }
        let heading = SyntaxClassifier.spans(for: "# weather in London",
                                             rates: Rates(), decimalPlaces: 7)[0]
        try expect(heading.filter { $0.role == .conversion }.isEmpty, "heading clean")
        let comment = SyntaxClassifier.spans(for: "// weather in London",
                                             rates: Rates(), decimalPlaces: 7)[0]
        try expect(comment.filter { $0.role == .conversion }.isEmpty, "comment clean")
        let token = SyntaxClassifier.spans(for: "weather in Lon\u{FFFC}don",
                                           rates: Rates(), decimalPlaces: 7)[0]
        try expect(token.filter { $0.role == .conversion }.isEmpty, "token line clean")
    },

    EngineCase("r55-source-city-uses-unit-role") {
        // The classifier paints the place with the EXISTING unit role —
        // no new role, no hardcoded color on the weather path.
        guard let syn = r55Source("Sources/NumlexCore/Engine/SyntaxHighlighting.swift") else {
            throw CaseFailure(message: "syntax source must exist", location: "R55Cases")
        }
        try expect(syn.contains("WeatherQuery.placeRange(in: line)"),
                   "range from shared parser", "shared")
        try expect(syn.contains("SyntaxSpan(role: .conversion, range: cityRange)"),
                   "city uses .conversion", "role")
    },

    EngineCase("r55-localization-keys") {
        let langs: [AppLanguage] = [.en, .ru, .de, .fr, .it, .zh]
        for lang in langs {
            let s = L10n.t("weatherUnavailable", language: lang)
            try expect(!s.isEmpty && s != "weatherUnavailable",
                       "translated for \(lang)", "key")
        }
        try expectEqual(L10n.t("weatherUnavailable", language: .en),
                        "Weather unavailable", "english")
        try expectEqual(L10n.t("weatherUnavailable", language: .ru),
                        "Погода недоступна", "russian exact")
    },
]

/// Mutable injected clock for TTL boundary tests.
private final class R55ClockBox: @unchecked Sendable {
    private let lock = NSLock()
    private var now: Date
    init(_ now: Date) { self.now = now }
    func get() -> Date { lock.lock(); defer { lock.unlock() }; return now }
    func set(_ d: Date) { lock.lock(); now = d; lock.unlock() }
}
