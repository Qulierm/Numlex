import Foundation
import NumlexCore

/// Package 8: the five weather query forms and the multi-metric snapshot.
/// Offline only — parsing, ranges, scanning, payload validation, cache
/// invalidation, evaluation selection and title/token behavior all run
/// against injected transports and fixtures.
private let WM8 = "\u{FFFC}"

private func weatherMetricSource(_ rel: String) -> String? {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let url = root.appendingPathComponent(rel).standardizedFileURL
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try? String(contentsOf: url, encoding: .utf8)
}

/// A full multi-metric snapshot for one place.
private func wmSnapshot(key: String = "london", display: String = "London",
                        current: Double = 18.5, apparent: Double = 17.25,
                        high: Double = 25.1, low: Double = 12.4,
                        fetchedAt: Date = Date()) -> WeatherSnapshot {
    WeatherSnapshot(queryKey: key, displayQuery: display, placeName: display,
                    country: "United Kingdom", latitude: 51.5074, longitude: -0.1278,
                    temperatureCelsius: current, fetchedAt: fetchedAt,
                    apparentCelsius: apparent, highCelsius: high, lowCelsius: low)
}

private func wmContext(_ snapshots: [WeatherSnapshot] = []) -> WeatherContext {
    let list = snapshots.isEmpty ? [wmSnapshot()] : snapshots
    return WeatherContext(snapshots: Dictionary(uniqueKeysWithValues: list.map { ($0.queryKey, $0) }))
}

private func wmSheet(_ content: String,
                     weather: WeatherContext,
                     decimalPlaces: Int = 2) -> [(result: LineResult, isTotal: Bool)] {
    let ids = content.components(separatedBy: "\n").map { _ in UUID() }
    return resolveSheet(content: content, lineIDs: ids, references: [],
                        rates: Rates(), decimalPlaces: decimalPlaces,
                        weather: weather).lines.map { ($0.result, $0.isTotal) }
}

/// The forecast payload the service validation reads (all four metrics).
private func wmForecast(temp: String = "18.5", apparent: String = "17.25",
                        high: String = "25.1", low: String = "12.4") -> Data {
    """
    {"current_units": {"temperature_2m": "°C", "apparent_temperature": "°C"},
     "current": {"temperature_2m": \(temp), "apparent_temperature": \(apparent)},
     "daily_units": {"temperature_2m_max": "°C", "temperature_2m_min": "°C"},
     "daily": {"temperature_2m_max": [\(high)], "temperature_2m_min": [\(low)]}}
    """.data(using: .utf8)!
}

private func wmGeocode() -> Data {
    """
    {"results": [{"name": "London", "country": "United Kingdom",
      "latitude": 51.5074, "longitude": -0.1278}]}
    """.data(using: .utf8)!
}

private final class WM8Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func increment() { lock.lock(); n += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return n }
}

private func wmRouter(forecast: Data, counter: WM8Counter? = nil) -> WeatherTransport {
    { request in
        counter?.increment()
        let url = request.url!
        let payload = url.host == WeatherEndpoints.geocodeHost ? wmGeocode() : forecast
        let response = HTTPURLResponse(url: url, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
        return (payload, response)
    }
}

private func wmAwait<T: Sendable>(_ label: String,
                                  _ body: @escaping @Sendable () async -> T) throws -> T {
    let sem = DispatchSemaphore(value: 0)
    let box = WM8Box<T>()
    Task { box.set(await body()); sem.signal() }
    if sem.wait(timeout: .now() + 10) == .timedOut {
        throw CaseFailure(message: "timeout: \(label)", location: "WeatherMetric")
    }
    guard let value = box.value else {
        throw CaseFailure(message: "no value: \(label)", location: "WeatherMetric")
    }
    return value
}

private final class WM8Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T?
    func set(_ v: T) { lock.lock(); stored = v; lock.unlock() }
    var value: T? { lock.lock(); defer { lock.unlock() }; return stored }
}

public let weatherMetricCases: [EngineCase] = [
    EngineCase("weather-five-forms-parse-with-kind-and-place") {
        let cases: [(String, WeatherQuery.Kind, String)] = [
            ("weather in London", .current, "London"),
            ("London temperature", .current, "London"),
            ("high in London", .high, "London"),
            ("low in London", .low, "London"),
            ("feels like in London", .apparent, "London"),
            // Case-insensitive keywords, flexible whitespace.
            ("WEATHER IN   London", .current, "London"),
            ("  High  In  New   York ", .high, "New York"),
            ("FEELS   LIKE in  Paris, France", .apparent, "Paris, France"),
            ("Kyoto TEMPERATURE", .current, "Kyoto"),
            // Multiword and non-ASCII places.
            ("weather in San Francisco", .current, "San Francisco"),
            ("high in Zürich", .high, "Zürich"),
            ("low in Нижний Новгород", .low, "Нижний Новгород"),
            ("feels like in 東京", .apparent, "東京"),
            ("Côte d'Ivoire temperature", .current, "Côte d'Ivoire"),
        ]
        for (line, kind, place) in cases {
            guard let q = WeatherQuery.parse(line) else {
                throw CaseFailure(message: "must parse: \(line)")
            }
            try expectEqual(q.kind, kind, "\(line) kind")
            try expectEqual(q.display, place, "\(line) display")
            try expectEqual(q.key, place.lowercased(), "\(line) place-only key")
        }
    },
    EngineCase("weather-strict-rejections") {
        // Empty place, assignments, tokens, operators, trailing garbage,
        // headings/comments and near-miss keywords never parse.
        let rejected = [
            "weather in",                     // empty place
            "weather in ",                    // whitespace-only place
            "in London",                      // missing keyword
            "weather London",                 // missing `in`
            "high in",                        // empty place
            "low in",                         // empty place
            "feels like in",                  // empty place
            "feels in London",                // wrong keyword
            "high London",                    // missing `in`
            "London high",                    // wrong suffix
            "weather in London + 5",          // operator
            "high in London * 2",             // operator
            "weather in London = 3",          // assignment
            "weather in London #tag",         // heading marker
            "weather in London \(WM8)",       // answer token
            "high in London, 5",              // trailing garbage with digits
            "weather in London - 5",          // hyphen beside a space
            "london temperature extra",       // trailing garbage
            "temperature",                    // no place
            "weather in London!extra",        // unsafe symbol
            "// weather in London",           // comment prefix is not this lane
            "# high in London",               // heading prefix
        ]
        for line in rejected {
            try expect(WeatherQuery.parse(line) == nil, "must reject: \(line)")
            try expect(WeatherQuery.placeRange(in: line) == nil, "no range: \(line)")
        }
    },
    EngineCase("weather-place-ranges-for-prefix-and-suffix-forms") {
        func range(_ line: String) throws -> (String, NSRange) {
            guard let r = WeatherQuery.placeRange(in: line) else {
                throw CaseFailure(message: "no range: \(line)")
            }
            let ns = line as NSString
            return (ns.substring(with: r), r)
        }
        let prefix = try range("weather in New York")
        try expectEqual(prefix.0, "New York", "prefix place text")
        try expectEqual(prefix.1, NSRange(location: 11, length: 8), "prefix range")
        let high = try range("high in London")
        try expectEqual(high.0, "London")
        try expectEqual(high.1, NSRange(location: 8, length: 6), "high range")
        let low = try range("  low in  Paris, France  ")
        try expectEqual(low.0, "Paris, France")
        try expectEqual(low.1, NSRange(location: 10, length: 13), "low range")
        let feels = try range("feels like in Côte d'Ivoire")
        try expectEqual(feels.0, "Côte d'Ivoire")
        try expectEqual(feels.1, NSRange(location: 14, length: 13), "apparent range")
        let suffix = try range("San Francisco temperature")
        try expectEqual(suffix.0, "San Francisco", "suffix place text")
        try expectEqual(suffix.1, NSRange(location: 0, length: 13), "suffix range")
        // A multiword place keeps its internal whitespace in the range.
        let upper = try range("WEATHER IN   New   York")
        try expectEqual(upper.0, "New   York", "range keeps original spacing")
    },
    EngineCase("weather-syntax-paints-only-the-place-for-every-form") {
        // Prefix and suffix forms alike: ONLY the place carries the unit
        // role; the keywords stay base text and `in` stays a specifier.
        func conversionRanges(_ line: String) throws -> [NSRange] {
            let s = SyntaxClassifier.spans(for: line, rates: Rates(), decimalPlaces: 7)[0]
            return s.filter { $0.role == .conversion }.map { $0.range }
        }
        try expectEqual(try conversionRanges("high in London"),
                        [NSRange(location: 8, length: 6)], "high")
        try expectEqual(try conversionRanges("low in London"),
                        [NSRange(location: 7, length: 6)], "low")
        try expectEqual(try conversionRanges("feels like in London"),
                        [NSRange(location: 14, length: 6)], "apparent")
        try expectEqual(try conversionRanges("London temperature"),
                        [NSRange(location: 0, length: 6)], "suffix form")
        try expectEqual(try conversionRanges("  high  in  New   York  "),
                        [NSRange(location: 12, length: 10)], "flexible whitespace")
        let specifier = SyntaxClassifier.spans(for: "high in London",
                                               rates: Rates(), decimalPlaces: 7)[0]
            .filter { $0.role == .specifier }.map { $0.range }
        try expectEqual(specifier, [NSRange(location: 5, length: 2)], "`in` specifier")
        // The classifier and the parser can never disagree.
        for line in ["high in London", "low in Paris, France",
                     "feels like in 東京", "Kyoto temperature"] {
            try expectEqual(WeatherQuery.placeRange(in: line),
                            try conversionRanges(line).first, "range parity: \(line)")
        }
    },
    EngineCase("weather-scan-dedupes-by-place-across-kinds") {
        // Every metric of one place shares ONE query: scan dedupes by the
        // place-only key while the FIRST line's kind is reported.
        let content = """
        weather in London
        high in London
        low in london
        London temperature
        feels like in London
        high in Paris
        """
        let queries = WeatherQuery.scanQueries(in: content)
        try expectEqual(queries.count, 2, "one query per place")
        try expectEqual(queries[0].key, "london")
        try expectEqual(queries[1].key, "paris")
        // The signature is place-only: adding a METRIC line for an
        // already-scanned place is not a new fetch trigger.
        let more = content + "\nfeels like in Paris\n"
        try expectEqual(WeatherQuery.signature(for: WeatherQuery.scanQueries(in: more)),
                        WeatherQuery.signature(for: queries),
                        "same places → same signature")
        // Headings, comments and malformed lines never produce requests.
        let hostile = """
        # high in London
        // low in London
        weather in London + 1
        high in
        """
        try expectEqual(WeatherQuery.scanQueries(in: hostile).count, 0)
    },
    EngineCase("weather-evaluation-selects-the-requested-metric") {
        let context = wmContext()
        let lines = wmSheet("""
        weather in London
        high in London
        low in London
        feels like in London
        London temperature
        """, weather: context)
        try expectEqual(lines.count, 5, "one row per logical line")
        try expectEqual(lines[0].result, .number(value: 18.5, unit: "C°"), "current")
        try expectEqual(lines[1].result, .number(value: 25.1, unit: "C°"), "high")
        try expectEqual(lines[2].result, .number(value: 12.4, unit: "C°"), "low")
        try expectEqual(lines[3].result, .number(value: 17.25, unit: "C°"), "apparent")
        try expectEqual(lines[4].result, .number(value: 18.5, unit: "C°"), "suffix = current")
        // A loading place stays quiet, an unknown place with a failure
        // mark shows the canonical unavailable message.
        let loading = wmSheet("high in Berlin", weather: .empty)
        try expectEqual(loading[0].result, .skip, "loading stays quiet")
        let failed = wmSheet("low in Berlin",
                             weather: WeatherContext(failedKeys: ["berlin"]))
        try expectEqual(failed[0].result, .error(message: "Weather unavailable"),
                        "terminal failure message")
    },
    EngineCase("weather-metrics-share-one-fetch-and-one-cache-entry") {
        let (dir, store) = try wmTempStore()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let counter = WM8Counter()
        let refresher = WeatherRefresher(
            store: store,
            transport: wmRouter(forecast: wmForecast(), counter: counter))
        // Every metric of one place shares ONE query key, so one fetch
        // (geocode + forecast) satisfies all of them from the cache.
        let current = WeatherQuery.parse("weather in London")!
        let high = WeatherQuery.parse("high in London")!
        let low = WeatherQuery.parse("low in London")!
        let first = try wmAwait("first") { await refresher.refresh(current) }
        let cachedHigh = try wmAwait("high") { await refresher.cachedSnapshot(for: high) }
        let cachedLow = try wmAwait("low") { await refresher.cachedSnapshot(for: low) }
        try expectEqual(first?.queryKey, "london")
        try expectEqual(cachedHigh?.queryKey, "london")
        try expectEqual(cachedLow?.queryKey, "london")
        // Geocode + forecast = 2 requests for three metrics of one place.
        try expectEqual(counter.count, 2, "one network pair per place")
        try expectEqual(store.load().keys.sorted(), ["london"], "one cache entry")
        // The single fetch installed EVERY metric.
        guard let snap = first, let highSnap = cachedHigh, let lowSnap = cachedLow else {
            throw CaseFailure(message: "no snapshot")
        }
        try expectClose(highSnap.highCelsius ?? -999, 25.1, 1e-9, "high from the same entry")
        try expectClose(lowSnap.lowCelsius ?? -999, 12.4, 1e-9, "low from the same entry")
        try expectClose(snap.temperatureCelsius, 18.5, 1e-9)
        try expectClose(snap.apparentCelsius ?? -999, 17.25, 1e-9)
        try expectClose(snap.highCelsius ?? -999, 25.1, 1e-9)
        try expectClose(snap.lowCelsius ?? -999, 12.4, 1e-9)
    },
    EngineCase("weather-endpoint-requests-every-metric") {
        guard let url = WeatherEndpoints.forecastURL(latitude: 51.5074, longitude: -0.1278),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            throw CaseFailure(message: "forecast URL must build")
        }
        let map = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value) })
        try expectEqual(map["current"], "temperature_2m,apparent_temperature")
        try expectEqual(map["daily"], "temperature_2m_max,temperature_2m_min")
        try expectEqual(map["forecast_days"], "1")
        try expectEqual(map["temperature_unit"], "celsius")
        try expectEqual(map["timezone"], "auto")
        try expectEqual(map["latitude"], "51.5074")
        try expectEqual(map["longitude"], "-0.1278")
        // No metric is requested twice and nothing else sneaks in.
        try expectEqual(items.count, 7, "exact query item count")
    },
    EngineCase("weather-legacy-cache-entries-are-invalidated-and-refetched") {
        // Pre-Package-8 cache bytes carry no apparent/high/low: they decode
        // but are INVALID, so the store drops them and the service refetches
        // instead of inventing a metric.
        let legacy = """
        {"queryKey":"london","displayQuery":"London","placeName":"London",
         "latitude":51.5074,"longitude":-0.1278,"temperatureCelsius":18.5,
         "fetchedAt":700000000}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(WeatherSnapshot.self, from: legacy)
        try expectEqual(decoded.temperatureCelsius, 18.5, "legacy temperature survives")
        try expect(decoded.apparentCelsius == nil, "no invented apparent value")
        try expect(decoded.highCelsius == nil, "no invented high value")
        try expect(decoded.lowCelsius == nil, "no invented low value")
        try expect(!decoded.isValid, "a legacy entry is invalid")
        try expectEqual(decoded.celsius(for: .high), nil, "no high to read")
        // The store drops it on load and a refresh installs the full entry.
        let (dir, store) = try wmTempStore()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let legacyFile = """
        {"entries": {"london": \(String(data: legacy, encoding: .utf8)!)}}
        """
        try legacyFile.write(toFile: store.fileURL.path, atomically: true, encoding: .utf8)
        try expectEqual(store.load().count, 0, "legacy entry dropped on load")
        let refresher = WeatherRefresher(store: store,
                                        transport: wmRouter(forecast: wmForecast()))
        let snap = try wmAwait("refetch") { await refresher.refresh(WeatherQuery.parse("high in London")!) }
        try expectClose(snap?.highCelsius ?? -999, 25.1, 1e-9, "refetched high")
        try expectClose(store.load()["london"]?.highCelsius ?? -999, 25.1, 1e-9, "persisted")
        // A stale last-good entry keeps winning over a failure, per metric.
        let stale = wmSnapshot(high: 30, fetchedAt: Date().addingTimeInterval(-3_600))
        let failing = WeatherRefresher(store: store,
                                       transport: { _ in throw URLError(.timedOut) })
        try wmAwait("seed") { await failing.inject(stale) }
        let kept = try wmAwait("stale") { await failing.refresh(WeatherQuery.parse("high in London")!) }
        try expectClose(kept?.highCelsius ?? -999, 30, 1e-9, "stale last-good kept")
    },
    EngineCase("weather-snapshot-validation-and-metric-projection") {
        let snap = wmSnapshot()
        try expect(snap.isValid, "a fully populated snapshot is valid")
        try expectClose(snap.celsius(for: .current) ?? -999, 18.5, 1e-9)
        try expectClose(snap.celsius(for: .apparent) ?? -999, 17.25, 1e-9)
        try expectClose(snap.celsius(for: .high) ?? -999, 25.1, 1e-9)
        try expectClose(snap.celsius(for: .low) ?? -999, 12.4, 1e-9)
        // The public initializer defaults omitted metrics to the current
        // temperature, so existing fixtures stay valid.
        let legacyStyle = WeatherSnapshot(queryKey: "london", displayQuery: "London",
                                          placeName: "London", country: nil,
                                          latitude: 0, longitude: 0,
                                          temperatureCelsius: 9, fetchedAt: Date())
        try expect(legacyStyle.isValid, "omitted metrics default to current")
        try expectClose(legacyStyle.apparentCelsius ?? -999, 9, 1e-9)
        // Out-of-range or inverted values are invalid whole.
        try expect(!wmSnapshot(high: 99).isValid, "high out of range")
        try expect(!wmSnapshot(low: -120).isValid, "low below range")
        try expect(!wmSnapshot(apparent: 500).isValid, "apparent out of range")
        try expect(!wmSnapshot(high: 5, low: 10).isValid, "inverted range")
        // Roundtrip keeps every metric (the cache file carries them).
        let data = try JSONEncoder().encode(snap)
        let back = try JSONDecoder().decode(WeatherSnapshot.self, from: data)
        try expectEqual(back, snap, "full roundtrip")
        try expectClose(back.highCelsius ?? -999, 25.1, 1e-9)
    },
    EngineCase("weather-payload-validation-for-every-metric") {
        func metrics(_ data: Data) throws -> WeatherForecastDocument.CelsiusMetrics? {
            try JSONDecoder().decode(WeatherForecastDocument.self, from: data).celsiusMetrics
        }
        guard let ok = try metrics(wmForecast()) else {
            throw CaseFailure(message: "the full payload must validate")
        }
        try expectClose(ok.current, 18.5, 1e-9)
        try expectClose(ok.apparent, 17.25, 1e-9)
        try expectClose(ok.high, 25.1, 1e-9)
        try expectClose(ok.low, 12.4, 1e-9)
        // Wrong unit in ANY block invalidates the whole document.
        let badUnit = """
        {"current_units": {"temperature_2m": "°C", "apparent_temperature": "°F"},
         "current": {"temperature_2m": 18.5, "apparent_temperature": 17.25},
         "daily_units": {"temperature_2m_max": "°C", "temperature_2m_min": "°C"},
         "daily": {"temperature_2m_max": [25.1], "temperature_2m_min": [12.4]}}
        """.data(using: .utf8)!
        let badUnitMetrics = try metrics(badUnit)
        try expect(badUnitMetrics == nil, "non-Celsius apparent unit")
        // Arrays must carry exactly one element each, and low <= high.
        for daily in ["[25.1, 26.0]", "[]", "[null]"] {
            let payload = """
            {"current_units": {"temperature_2m": "°C", "apparent_temperature": "°C"},
             "current": {"temperature_2m": 18.5, "apparent_temperature": 17.25},
             "daily_units": {"temperature_2m_max": "°C", "temperature_2m_min": "°C"},
             "daily": {"temperature_2m_max": \(daily), "temperature_2m_min": [12.4]}}
            """.data(using: .utf8)!
            let payloadMetrics = try metrics(payload)
            try expect(payloadMetrics == nil, "bad daily array: \(daily)")
        }
        let inverted = """
        {"current_units": {"temperature_2m": "°C", "apparent_temperature": "°C"},
         "current": {"temperature_2m": 18.5, "apparent_temperature": 17.25},
         "daily_units": {"temperature_2m_max": "°C", "temperature_2m_min": "°C"},
         "daily": {"temperature_2m_max": [10], "temperature_2m_min": [20]}}
        """.data(using: .utf8)!
        let invertedMetrics = try metrics(inverted)
        try expect(invertedMetrics == nil, "low > high")
    },
    EngineCase("weather-token-and-title-behavior-for-every-metric") {
        // A token on a HIGH row shows the daily maximum and still converts.
        let u0 = UUID(), u1 = UUID()
        let content = "high in London\n" + WM8 + " to fahrenheit"
        let (lines, tokens) = resolveSheet(
            content: content, lineIDs: [u0, u1],
            references: [AnswerReference(sourceLineID: u0, labelLine: 1, location: 15)],
            rates: Rates(), decimalPlaces: 7, weather: wmContext())
        try expectEqual(lines[0].result, .number(value: 25.1, unit: "C°"), "high row")
        if case .active(let value, let unit, _) = tokens[0].state {
            try expectClose(value, 25.1, 1e-9, "the token's source value is the daily high")
            try expectEqual(unit, "C°", "source unit")
        } else {
            throw CaseFailure(message: "token must be active: \(tokens[0].state)")
        }
        // The CONSUMER row is the converted value: 25.1 C = 77.18 F.
        if case .number(let v, let u, _, _) = lines[1].result {
            try expectClose(v, 77.18, 1e-9, "the token line converts the daily high to F")
            try expectEqual(u, "F°", "converted unit label")
        } else {
            throw CaseFailure(message: "token line must convert: \(lines[1].result)")
        }
        // Auto-titles recognize every form (pure, before any network).
        for (line, expected) in [("high in London", "high in London"),
                                 ("low in Paris", "low in Paris"),
                                 ("feels like in Nice", "feels like in Nice"),
                                 ("Kyoto temperature", "Kyoto temperature")] {
            try expectEqual(Sheet.autoTitle(from: line, fallback: "Sheet"), expected,
                            "title: \(line)")
        }
        // Previous-answer planning sees the ready metric too: the LOW row
        // is an ordinary finite number and qualifies as the source.
        let content2 = "low in London\n"
        let ids2 = [UUID(), UUID()]
        guard let plan = PreviousAnswerPlan.plan(content: content2, lineIDs: ids2,
                                                caret: (content2 as NSString).length,
                                                op: "+", weather: wmContext()) else {
            throw CaseFailure(message: "the low row must qualify as a previous answer")
        }
        try expectEqual(plan.sourceLineIndex, 0, "the low line is the source")
        try expectEqual(plan.sourceLineID, ids2[0], "source identity")
        try expectEqual(plan.operatorCharacter, "+")
    },
    EngineCase("weather-source-contracts-and-persistence-untouched") {
        guard let query = weatherMetricSource("Sources/NumlexCore/Engine/WeatherQuery.swift"),
              let service = weatherMetricSource("Sources/NumlexCore/Services/WeatherService.swift"),
              let evaluator = weatherMetricSource("Sources/NumlexCore/Engine/Evaluator.swift"),
              let app = weatherMetricSource("Sources/NumlexApp/AppModel.swift")
        else {
            throw CaseFailure(message: "weather sources missing")
        }
        // ONE grammar feeds parse and placeRange (no drift).
        try expect(!query.contains("NSRegularExpression"), "no regex evaluator")
        try expect(query.contains("static func grammar(_ line: String)"),
                   "one grammar function")
        try expectEqual(query.components(separatedBy: "grammar(line)").count - 1, 2,
                        "parse and placeRange both consume the grammar")
        // The key stays place-only; the kind is per line.
        try expect(query.contains("WeatherQuery(key: display.lowercased(), display: display, kind: g.kind)"),
                   "key is the place, kind travels separately")
        // The service requests and validates every metric.
        try expect(service.contains("\"temperature_2m,apparent_temperature\""),
                   "current metrics requested together")
        try expect(service.contains("\"temperature_2m_max,temperature_2m_min\""),
                   "daily metrics requested together")
        try expect(service.contains("URLQueryItem(name: \"forecast_days\", value: \"1\")"),
                   "exactly one forecast day")
        // Evaluation selects the metric from the place's snapshot.
        try expect(evaluator.contains("snap.celsius(for: query.kind)"),
                   "the evaluator reads the requested metric")
        // Weather never enters the store or `.nlx`.
        try expect(!app.contains("weatherSnapshots = payload"),
                   "weather state is never persisted into the store")
        let export = weatherMetricSource("Sources/NumlexCore/Models/Sheet.swift")
        try expect(export?.contains("public var weather") == false,
                   "Sheet/SheetExport carry no weather field")
    }
]

private func wmTempStore() throws -> (dir: String, store: WeatherStore) {
    let dir = NSTemporaryDirectory() + "numlex-wm8-" + UUID().uuidString
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    return (dir, WeatherStore(directory: URL(fileURLWithPath: dir)))
}
