//
//  R85Cases.swift
//  NumlexTestKit
//
//  R85: exact integer bases (0x/0b/0o literals, base converters,
//  bitwise operators, the base functions) and geography (coordinates,
//  Haversine, DMS, place queries). The exact lane pins the R85
//  contract on top of the legacy suite: full Int64 truth (never a
//  Double), strict line ownership, and the shared context threading.
//

import NumlexCore
import Foundation

/// The R85 case collection (all tasks).
public var r85Cases: [EngineCase] {
    r85BaseCases + r85BitwiseCases + r85IntegerUiCases
    + r85GeoMathCases + r85GeoQueryCases + r85GeoServiceCases
    + r85GeoAppCases + r85BaseFormatCases
}

// MARK: - helpers

/// Evaluates a whole sheet with the shared fixed clock (geography and
/// base lines are clock-free; the context keeps date lines stable).
@discardableResult
func r85Sheet(_ source: String,
              rates: Rates = Rates(),
              context: NumberFormatContext = .legacy,
              unitContext: UnitContext = .builtIns,
              weather: WeatherContext = .empty,
              geo: GeoContext = .empty,
              now: Date = r84Now,
              calendar: Calendar = r84Calendar) -> [SheetLine] {
    var vars: [String: Double] = [:]
    return evaluateSheet(source, variables: &vars, rates: rates,
                         decimalPlaces: 6, now: now, calendar: calendar,
                         weather: weather, geo: geo,
                         context: context, unitContext: unitContext)
}

func r85Int(_ line: SheetLine) -> (value: Int64, radix: Int)? {
    guard case .integer(let v, let r) = line.result else { return nil }
    return (v, r)
}

func r85IntText(_ line: SheetLine, context: NumberFormatContext = .legacy) -> String? {
    guard case .integer(let v, let r) = line.result else { return nil }
    if r == 10 { return IntLiteral.formatDecimal(v, context: context) }
    return IntLiteral.format(v, radix: r)
}

func r85Value(_ line: SheetLine) -> Double? {
    guard case .number(let v, _, _, _) = line.result else { return nil }
    return v
}

func r85IsError(_ line: SheetLine) -> Bool {
    if case .error = line.result { return true }
    return false
}

func r85Close(_ a: Double?, _ b: Double, _ msg: String = "value") throws {
    guard let a else {
        throw CaseFailure(message: "\(msg): expected \(b), got no value")
    }
    guard abs(a - b) <= 1e-6 * max(1, abs(b)) else {
        throw CaseFailure(message: "\(msg): \(a) !~ \(b)")
    }
}

// MARK: - 1-2: base conversions, literals, functions

let r85BaseCases: [EngineCase] = [
    EngineCase("r85-base-conversions") {
        // The contract examples, alias spellings included.
        try expectEqual(r85IntText(r85Sheet("256 as hex")[0]), "0x100")
        try expectEqual(r85IntText(r85Sheet("99 in binary")[0]), "0b1100011")
        try expectEqual(r85IntText(r85Sheet("0x9F31 to decimal")[0]), "40,753")
        try expectEqual(r85IntText(r85Sheet("0b1000101 to octal")[0]), "0o105")
        try expectEqual(r85IntText(r85Sheet("0b101101 as base 8")[0]), "0o55")
        try expectEqual(r85IntText(r85Sheet("0x2D as base 2")[0]), "0b101101")
        // Aliases: decimal/base10, binary/base2, octal/base8,
        // hex/hexadecimal/base16.
        try expectEqual(r85IntText(r85Sheet("5 as hexadecimal")[0]), "0x5")
        try expectEqual(r85IntText(r85Sheet("5 as base16")[0]), "0x5")
        try expectEqual(r85IntText(r85Sheet("5 to base10")[0]), "5")
        try expectEqual(r85IntText(r85Sheet("5 to base2")[0]), "0b101")
        try expectEqual(r85IntText(r85Sheet("5 to base8")[0]), "0o5")
        // The explicit target wins over the literal's radix.
        try expectEqual(r85IntText(r85Sheet("0xFF to decimal")[0]), "255")
        // Strictness: unknown base names are NOT phrases.
        try r85ExpectNotPhrase("256 as base 7")
        try r85ExpectNotPhrase("256 as decima")
    },
    EngineCase("r85-base-functions") {
        // int/bin/oct/hex on the exact lane (presentation radix rides
        // the function).
        try expectEqual(r85IntText(r85Sheet("int(0o55)")[0]), "45")
        try expectEqual(r85IntText(r85Sheet("hex(99)")[0]), "0x63")
        try expectEqual(r85IntText(r85Sheet("bin(0x73)")[0]), "0b1110011")
        try expectEqual(r85IntText(r85Sheet("oct(69)")[0]), "0o105")
        // Functions compose with arithmetic.
        try expectEqual(r85IntText(r85Sheet("hex(99) + 1")[0]), "0x64")
        // Strict arguments: non-integer and overflow are errors.
        try r85IsErrorLine(r85Sheet("hex(3.5)")[0], "hex(3.5)")
        try r85IsErrorLine(r85Sheet("int(1e100)")[0], "int overflow")
    },
    EngineCase("r85-literal-strictness") {
        // Underscores: between digits only, single, never at an edge.
        try expectEqual(r85IntText(r85Sheet("0x1_0")[0]), "0x10")
        try expectEqual(r85IntText(r85Sheet("100_000 as hex")[0]), "0x186A0")
        try r85IsErrorLine(r85Sheet("0x_1F")[0], "leading underscore")
        try r85IsErrorLine(r85Sheet("0x1F_")[0], "trailing underscore")
        try r85IsErrorLine(r85Sheet("0x1__F")[0], "doubled underscore")
        // Digit-set strictness.
        try r85IsErrorLine(r85Sheet("0b102")[0], "binary digit")
        try r85IsErrorLine(r85Sheet("0o8")[0], "octal digit")
        // Overflow: 65+ binary digits and the Int64 edges.
        try r85IsErrorLine(r85Sheet("0b" + String(repeating: "1", count: 65))[0], "binary overflow")
        try expectEqual(r85IntText(r85Sheet("0x7FFFFFFFFFFFFFFF")[0]), "0x7FFFFFFFFFFFFFFF")
        try expectEqual(r85IntText(r85Sheet("-0x7FFFFFFFFFFFFFFF as base 10")[0]), "-9,223,372,036,854,775,807")
        // Negatives are signed-magnitude; the lattice stays exact.
        try expectEqual(r85IntText(r85Sheet("-0x10 + 1")[0]), "-15")
        // Prose with a lone & stays prose (no false error).
        let prose = r85Sheet("fish & chips")[0].result
        if case .error = prose { throw CaseFailure(message: "fish & chips must stay prose") }
        // Digit-bearing & lines are strict math.
        try r85IsErrorLine(r85Sheet("1 & 2 &")[0], "dangling &")
    },
]

private func r85ExpectNotPhrase(_ line: String) throws {
    // A non-phrase line is NOT owned by the exact lane: it keeps the
    // legacy outcome (an ordinary error from the later lanes — never
    // the exact lane's presentation).
    guard BasePhrase.match(line) == nil else {
        throw CaseFailure(message: "\(line) must not be a base phrase")
    }
}

private func r85IsErrorLine(_ line: SheetLine, _ label: String) throws {
    guard case .error = line.result else {
        throw CaseFailure(message: "\(label): expected an error, got \(line.result)")
    }
}

// MARK: - 3: bitwise operators

let r85BitwiseCases: [EngineCase] = [
    EngineCase("r85-bitwise-core") {
        try expectEqual(r85IntText(r85Sheet("3 & 5")[0]), "1")
        try expectEqual(r85IntText(r85Sheet("255 & 0b11001100")[0]), "0b11001100")
        try expectEqual(r85IntText(r85Sheet("0x10 | 3")[0]), "0x13")
        try expectEqual(r85IntText(r85Sheet("0b101 xor 0b011")[0]), "0b110")
        try expectEqual(r85IntText(r85Sheet("1 << 4")[0]), "16")
        try expectEqual(r85IntText(r85Sheet("0xFF << 1")[0]), "0x1FE")
        try expectEqual(r85IntText(r85Sheet("4 >> 2")[0]), "1")
        try expectEqual(r85IntText(r85Sheet("1024 >> 10")[0]), "1")
    },
    EngineCase("r85-bitwise-word-forms") {
        // Contextual word and/or: numeric math on BOTH sides.
        try expectEqual(r85IntText(r85Sheet("3 and 5")[0]), "1")
        try expectEqual(r85IntText(r85Sheet("3 or 5")[0]), "7")
        try expectEqual(r85IntText(r85Sheet("3 and 5 or 8")[0]), "9")
        try expectEqual(r85IntText(r85Sheet("0xF and 0x3")[0]), "0x3")
    },
    EngineCase("r85-bitwise-precedence") {
        // C-like: & tighter than xor, xor tighter than |, shifts
        // above all of them.
        try expectEqual(r85IntText(r85Sheet("1 | 2 & 4")[0]), "1")
        try expectEqual(r85IntText(r85Sheet("(1 | 2) & 4")[0]), "0")
        try expectEqual(r85IntText(r85Sheet("1 << 2 | 1")[0]), "5")  // 1<<2=4, 4|1=5
        try expectEqual(r85IntText(r85Sheet("15 xor 3 and 12")[0]), "12")  // word `and` sits at the logical level (below `xor`); the glyph `&` is C-precedence
        // Shift overflow is a visible error (shape-owned line).
        try r85IsErrorLine(r85Sheet("1 << 64")[0], "shift 64")
        try r85IsErrorLine(r85Sheet("1 >> 70")[0], "shift 70")
    },
    EngineCase("r85-bitwise-tokens-variables") {
        // A base variable rides its own presentation.
        let sheet = r85Sheet("x = 0x1F\nx\nx & 1\nx + 1\nx as hex")
        try expectEqual(r85IntText(sheet[1]), "0x1F")
        try expectEqual(r85IntText(sheet[2]), "0x1")
        try expectEqual(r85IntText(sheet[3]), "0x20")
        try expectEqual(r85IntText(sheet[4]), "0x1F")
    },
]

// MARK: - 4: DMS / degree math (pure, context-free)

let r85GeoMathCases: [EngineCase] = [
    EngineCase("r85-dms-conversion") {
        try expectEqual(
            r85Sheet("156.742 as DMS")[0].result,
            .dms(DMSTools.fromDecimal(156.742)!),
            "156.742 as DMS")
        let back = r85Sheet("156° 44′ 31.2″ as decimal")[0]
        try r85Close(r85Value(back), 156.742)
        try expectEqual(r85Value(back) != nil, true, "dms as decimal")
    },
    EngineCase("r85-dms-runs") {
        // Bare DMS runs are decimal angles with a degree unit.
        let a = r85Sheet("156° 44′ 31.2″")[0]
        try r85Close(r85Value(a), 156.742)
        let b = r85Sheet("156° 44′ 31″")[0]
        try r85Close(r85Value(b), 156 + 44.0 / 60 + 31.0 / 3600)
        // The degree-only spelling.
        let c = r85Sheet("156° as decimal")[0]
        try r85Close(r85Value(c), 156)
    },
    EngineCase("r85-degree-cardinals") {
        try r85Close(r85Value(r85Sheet("48.8566° N")[0]), 48.8566)
        try r85Close(r85Value(r85Sheet("48.8566° S")[0]), -48.8566)
        try r85Close(r85Value(r85Sheet("2.3522° W")[0]), -2.3522)
        try r85Close(r85Value(r85Sheet("2.3522° E")[0]), 2.3522)
        try r85Close(r85Value(r85Sheet("-30° S")[0]), -30, "explicit sign wins")
    },
    EngineCase("r85-degree-prose-safety") {
        // Prose with a glued degree is NOT owned — it stays skip.
        let prose = r85Sheet("It's 5° today")[0].result
        if case .error = prose { throw CaseFailure(message: "prose degree line must not error") }
        // A garbage owned shape errors (it carries a prime, so it IS owned).
        try r85IsErrorLine(r85Sheet("156° 44′ garbage")[0], "dms garbage")
    },
    EngineCase("r85-haversine") {
        let london = GeoCoordinate(latitude: 51.5074, longitude: -0.1278)
        let paris = GeoCoordinate(latitude: 48.8566, longitude: 2.3522)
        let m = Haversine.meters(between: london, and: paris)
        // The contract: about 343.5 km (pin with a generous but real
        // band: 340–347 km at R = 6,371,008.8 m).
        try expect(m / 1000 > 340 && m / 1000 < 347, "London-Paris = \(m / 1000) km")
        // Same point is exactly zero; the antipodal edge is the half
        // circumference.
        try expectEqual(Haversine.meters(between: london, and: london), 0.0)
        let anti = Haversine.meters(between: GeoCoordinate(latitude: 0, longitude: 0),
                                    and: GeoCoordinate(latitude: 0, longitude: 180))
        try expect(anti > 20_000_000 && anti < 20_100_000, "antipodal \(anti)")
    },
    EngineCase("r85-coordinate-validation") {
        try expect(!GeoCoordinate(latitude: 91, longitude: 0).isValid, "lat 91")
        try expect(!GeoCoordinate(latitude: 0, longitude: 181).isValid, "lon 181")
        try expect(!GeoCoordinate(latitude: .nan, longitude: 0).isValid, "nan lat")
        try expect(GeoCoordinate(latitude: -90, longitude: 180).isValid, "corners valid")
    },
]

// MARK: - 5: geo query parsing + evaluation with a seeded context

private func r85Snap(placeKey: String, name: String, lat: Double, lon: Double) -> GeoSnapshot {
    GeoSnapshot(placeKey: placeKey, displayPlace: name, placeName: name,
                country: nil, latitude: lat, longitude: lon,
                fetchedAt: Date(timeIntervalSince1970: 1_700_000_000))
}

private let r85London = r85Snap(placeKey: "london", name: "London", lat: 51.5074, lon: -0.1278)
private let r85Paris = r85Snap(placeKey: "paris", name: "Paris", lat: 48.8566, lon: 2.3522)

let r85GeoQueryCases: [EngineCase] = [
    EngineCase("r85-geo-parse-shapes") {
        try expect(GeoQueryParse.parse("location of London") != nil)
        try expect(GeoQueryParse.parse("LOCATION OF london") != nil)
        try expect(GeoQueryParse.parse("latitude of Paris") != nil)
        try expect(GeoQueryParse.parse("longitude of \"New York\"") != nil)
        try expect(GeoQueryParse.parse("distance between London and Paris") != nil)
        // Strict negatives: not geo lines.
        try expect(GeoQueryParse.parse("distance between London") == nil, "single endpoint")
        try expect(GeoQueryParse.parse("location of") == nil, "empty place")
        try expect(GeoQueryParse.parse("the location of London is nice") == nil, "embedded")
        try expect(GeoQueryParse.parse("0x1F") == nil, "base line is not geo")
        try expect(GeoQueryParse.parse("fish & chips") == nil, "prose is not geo")
    },
    EngineCase("r85-geo-coordinate-endpoints") {
        let q = GeoQueryParse.parse(
            "distance between 51.5074° N, 0.1278° W and 48.8566° N, 2.3522° E")
        try expect(q != nil, "coordinate-pair endpoints parse")
    },
    EngineCase("r85-geo-evaluation-ready") {
        let geo = GeoContext(snapshots: ["london": r85London, "paris": r85Paris])
        let sheet = r85Sheet(
            """
            location of London
            latitude of Paris
            longitude of London
            distance between London and Paris
            """,
            geo: geo)
        // location → the coordinate pair.
        guard case .location(let name, _, let coord) = sheet[0].result else {
            throw CaseFailure(message: "location of London: \(sheet[0].result)")
        }
        try expectEqual(name, "London")
        try r85Close(coord.latitude, 51.5074)
        try r85Close(coord.longitude, -0.1278)
        try r85Close(r85Value(sheet[1]), 48.8566)
        try r85Close(r85Value(sheet[2]), -0.1278)
        // The contract: about 343.5 km, a km-unit number answer.
        try r85Close(r85Value(sheet[3]), 343.5565, "London-Paris km")
        guard case .number(_, let unit, _, _) = sheet[3].result else {
            throw CaseFailure(message: "distance unit: \(sheet[3].result)")
        }
        try expectEqual(unit, "km")
    },
    EngineCase("r85-geo-loading-and-failure") {
        // A pending place with NO cache is quiet (skip) — no spinner,
        // no error.
        let loading = GeoContext(pendingKeys: ["tokyo"])
        try expectEqual(r85Sheet("location of Tokyo", geo: loading)[0].result, .skip)
        // A known place failing to refresh with a cache shows the cache.
        let stale = GeoContext(snapshots: ["paris": r85Paris], failedKeys: ["paris"])
        let cached = r85Sheet("location of Paris", geo: stale)[0]
        if case .location = cached.result { } else {
            throw CaseFailure(message: "stale last-good: \(cached.result)")
        }
        // Failed with NO cache: the quiet error line.
        let dead = GeoContext(failedKeys: ["atlantis"])
        let err = r85Sheet("location of Atlantis", geo: dead)[0]
        try r85IsErrorLine(err, "unavailable location")
        // Distance: one endpoint loading → the whole line is quiet.
        let mixed = GeoContext(snapshots: ["london": r85London], pendingKeys: ["rome"])
        try expectEqual(r85Sheet("distance between London and Rome", geo: mixed)[0].result, .skip)
    },
    EngineCase("r85-geo-scan-signature") {
        let content = "location of London\nlocation of London\ndistance between London and Paris"
        let qs = GeoQueryParse.scanQueries(in: content)
        try expectEqual(qs.count, 2, "dedupe by key")
        let sig = GeoQueryParse.signature(for: qs)
        try expect(sig.contains("\n"), "signature joins keys")
    },
]

// MARK: - 6: geo service (store + refresher, mock transport, offline)

private final class R85Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<T, Error>?
    var done: Result<T, Error>? { lock.lock(); defer { lock.unlock() }; return result }
    func set(_ r: Result<T, Error>) { lock.lock(); result = r; lock.unlock() }
}

private final class R85Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var d: Date
    init(_ d: Date) { self.d = d }
    var value: Date { lock.lock(); defer { lock.unlock() }; return d }
    func set(_ d: Date) { lock.lock(); self.d = d; lock.unlock() }
}

private func r85Await<T: Sendable>(
    _ location: String,
    _ op: @escaping @Sendable () async throws -> T
) throws -> T {
    let box = R85Box<T>()
    let sem = DispatchSemaphore(value: 0)
    Task {
        do { box.set(.success(try await op())) }
        catch { box.set(.failure(error)) }
        sem.signal()
    }
    guard sem.wait(timeout: .now() + 30) == DispatchTimeoutResult.success else {
        throw CaseFailure(message: "operation timed out", location: location)
    }
    guard let r = box.done else { throw CaseFailure(message: "no result", location: location) }
    return try r.get()
}

private final class R85Counter: @unchecked Sendable {
    let lock = NSLock()
    private var n = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
    func increment() { lock.lock(); n += 1; lock.unlock() }
}

private func r85HTTP(_ url: URL, status: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
}

private func r85GeocodeJSON(name: String = "Paris",
                            country: String? = "France",
                            lat: Double = 48.8566,
                            lon: Double = 2.3522) -> Data {
    let c = country.map { "\"country\": \"\($0)\"," } ?? ""
    return """
    {"results": [{"name": "\(name)", \(c) "admin1": "IDF",
     "latitude": \(lat), "longitude": \(lon)}]}
    """.data(using: .utf8)!
}

private func r85TempDir() throws -> URL {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("numlex-geo-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

let r85GeoServiceCases: [EngineCase] = [
    EngineCase("r85-geostore-roundtrip") {
        let dir = try r85TempDir()
        let store = GeoStore(directory: dir)
        try expectEqual(store.load().count, 0, "fresh dir")
        let ok = r85Snap(placeKey: "paris", name: "Paris", lat: 48.8566, lon: 2.3522)
        let bad = r85Snap(placeKey: "nowhere", name: "X", lat: 999, lon: 0)
        try expect(store.save(["paris": ok, "nowhere": bad]), "atomic save")
        let loaded = store.load()
        try expectEqual(loaded.count, 1, "invalid entries drop on load")
        try expectEqual(loaded["paris"]?.latitude, 48.8566)
        try expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("locations.json").path))
    },
    EngineCase("r85-geostore-corrupt") {
        let dir = try r85TempDir()
        let store = GeoStore(directory: dir)
        try Data("not json at all".utf8).write(to: dir.appendingPathComponent("locations.json"))
        try expectEqual(store.load().count, 0, "corrupt file loads empty")
    },
    EngineCase("r85-refresher-success") {
        let dir = try r85TempDir()
        let store = GeoStore(directory: dir)
        let transport: WeatherTransport = { request in
            guard request.url?.host == WeatherEndpoints.geocodeHost else {
                throw URLError(.unsupportedURL)
            }
            return (r85GeocodeJSON(), r85HTTP(request.url!, status: 200))
        }
        let refresher = GeoRefresher(store: store, transport: transport)
        let snap = try r85Await("geo-refresh-success") {
            await refresher.refresh(displayPlace: "Paris", placeKey: "paris")
        }
        try expect(snap != nil, "snapshot installed")
        try expectEqual(snap?.latitude, 48.8566)
        // Persisted to the file cache.
        try expectEqual(store.load()["paris"]?.placeName, "Paris")
    },
    EngineCase("r85-refresher-stale-wins") {
        let dir = try r85TempDir()
        let store = GeoStore(directory: dir)
        let stale = r85Snap(placeKey: "rome", name: "Rome", lat: 41.9, lon: 12.5)
        let failing: WeatherTransport = { _ in throw URLError(.notConnectedToInternet) }
        let refresher = GeoRefresher(store: store, transport: failing)
        try r85Await("geo-inject") { await refresher.inject(stale) }
        let out = try r85Await("geo-stale") {
            await refresher.refresh(displayPlace: "Rome", placeKey: "rome")
        }
        // The last-good snapshot survives the failed refresh.
        try expectEqual(out?.latitude, 41.9)
        try expectEqual(store.load()["rome"]?.latitude, 41.9)
    },
    EngineCase("r85-refresher-single-flight") {
        let dir = try r85TempDir()
        let store = GeoStore(directory: dir)
        let counter = R85Counter()
        let transport: WeatherTransport = { request in
            counter.increment()
            try? await Task.sleep(for: .milliseconds(50))
            return (r85GeocodeJSON(), r85HTTP(request.url!, status: 200))
        }
        let refresher = GeoRefresher(store: store, transport: transport)
        try r85Await("geo-dedupe") {
            await withTaskGroup(of: GeoSnapshot?.self) { group in
                group.addTask { await refresher.refresh(displayPlace: "Paris", placeKey: "paris") }
                group.addTask { await refresher.refresh(displayPlace: "Paris", placeKey: "paris") }
            }
        }
        try expectEqual(counter.value, 1, "one flight for the same place")
    },
    EngineCase("r85-refresher-ttl") {
        let dir = try r85TempDir()
        let store = GeoStore(directory: dir)
        let clock = R85Clock(Date(timeIntervalSince1970: 1_700_000_000))
        let refresher = GeoRefresher(store: store,
                                     transport: { _ in throw URLError(.notConnectedToInternet) },
                                     now: { clock.value })
        let snap = r85Snap(placeKey: "oslo", name: "Oslo", lat: 59.91, lon: 10.75)
        try r85Await("geo-ttl-inject") { await refresher.inject(snap) }
        clock.set(snap.fetchedAt.addingTimeInterval(GeoRefresher.cacheTTL - 1))
        try expectEqual(try r85Await("ttl-under") { await refresher.isStale("oslo") }, false)
        clock.set(snap.fetchedAt.addingTimeInterval(GeoRefresher.cacheTTL + 1))
        try expectEqual(try r85Await("ttl-over") { await refresher.isStale("oslo") }, true)
        try expectEqual(try r85Await("ttl-missing") { await refresher.isStale("bergen") }, true)
    },
    EngineCase("r85-refresher-geocode-only") {
        // The geography service must ONLY hit the geocode host — the
        // forecast endpoint is never requested by a geo refresh.
        let dir = try r85TempDir()
        let store = GeoStore(directory: dir)
        let hosts: WeatherTransport = { request in
            let url = request.url!
            if url.host == WeatherEndpoints.geocodeHost {
                return (r85GeocodeJSON(), r85HTTP(url, status: 200))
            }
            throw URLError(.unsupportedURL) // any forecast hit fails the test
        }
        let refresher = GeoRefresher(store: store, transport: hosts)
        let snap = try r85Await("geo-only") {
            await refresher.refresh(displayPlace: "Paris", placeKey: "paris")
        }
        try expect(snap != nil, "geocode-only refresh succeeds")
    },
]

// MARK: - 7: app-level threading (sheet evaluation with a geo context)

let r85GeoAppCases: [EngineCase] = [
    EngineCase("r85-geo-sheet-mixed") {
        let geo = GeoContext(snapshots: ["london": r85London, "paris": r85Paris])
        let sheet = r85Sheet(
            """
            256 as hex
            location of London
            0xFF << 1
            distance between Paris and London
            48.8566° N
            156.742 as DMS
            """,
            geo: geo)
        try expectEqual(r85IntText(sheet[0]), "0x100")
        guard case .location = sheet[1].result else {
            throw CaseFailure(message: "geo location: \(sheet[1].result)")
        }
        try expectEqual(r85IntText(sheet[2]), "0x1FE")
        try r85Close(r85Value(sheet[3]), 343.5565)
        try r85Close(r85Value(sheet[4]), 48.8566)
        guard case .dms = sheet[5].result else {
            throw CaseFailure(message: "dms line: \(sheet[5].result)")
        }
    },
    EngineCase("r85-geo-empty-context") {
        // No cache at all: every geo line is the quiet unavailable
        // error — never a number, never a crash.
        let sheet = r85Sheet("location of London\ndistance between London and Paris")
        try r85IsErrorLine(sheet[0], "no-cache location")
        try r85IsErrorLine(sheet[1], "no-cache distance")
    },
]

// MARK: - 8: base presentation / formatting protections

let r85IntegerUiCases: [EngineCase] = [
    EngineCase("r85-integer-answers-ui") {
        // The answer menu: base answers are Copy/Delete only (no
        // rounding); numeric answers keep their rounding submenu.
        let base = r85Sheet("255 & 0b11001100")[0].result
        guard case .integer = base else {
            throw CaseFailure(message: "base answer: \(base)")
        }
        let m = AnswerDisplay.menu(for: base)
        try expectEqual(m?.showsActions, true)
        try expectEqual(m?.showsRounding, false)
        let num = r85Sheet("1 + 2")[0].result
        let mn = AnswerDisplay.menu(for: num)
        try expectEqual(mn?.showsRounding, true)
        // Base answers contribute their EXACT value to totals.
        let total = r85Sheet("1 & 3\n2 | 4\ntotal")[2].result
        guard case .number(let tv, _, _, _) = total else {
            throw CaseFailure(message: "total: \(total)")
        }
        try r85Close(tv, 7, "1 & 3 = 1, 2 | 4 = 6, total = 7")
    },
]

let r85BaseFormatCases: [EngineCase] = [
    EngineCase("r85-decimal-presentation-contexts") {
        // Decimal presentation of a base answer follows the active
        // number context (grouping separators included).
        let line = r85Sheet("0x9F31 as decimal")[0].result
        guard case .integer(let v, let radix) = line else {
            throw CaseFailure(message: "0x9F31 as decimal: \(line)")
        }
        try expectEqual(v, 40753)
        try expectEqual(radix, 10)
        let legacy = AnswerDisplay.text(for: line, decimalPlaces: 6, context: .legacy)
        try expectEqual(legacy, "40,753")
        let west = NumberFormatContext.resolve(
            RegionalNumberPreferences(region: .westernEurope,
                                      convertForeignOnPaste: false,
                                      showThousandsSeparator: true,
                                      useCompactNotation: false))
        try expectEqual(AnswerDisplay.text(for: line, decimalPlaces: 6, context: west),
                        "40.753")
    },
    EngineCase("r85-radix-literals-stay-intact-on-input") {
        // r85: `0x`/`0b`/`0o` literals are NEVER rewritten by the
        // input pipeline: quick-operator `x` protection and no digit
        // grouping inside radix literals.
        let prefs = InputPreferences(padOperators: true, replaceAsterisk: true,
                                     replaceBacktick: true, quickOperators: true,
                                     groupNumbers: true, insertPreviousAnswer: false)
        // nil means the line came back byte-identical — intact.
        // A non-nil result must never have mangled a radix prefix.
        if let f1 = InputFormatting.formatLine("0xDEADBEEF", prefs: prefs),
           !f1.text.hasPrefix("0x") {
            throw CaseFailure(message: "formatLine mangled hex x: \(f1.text)")
        }
        if let f2 = InputFormatting.formatLine("0x1F << 4", prefs: prefs),
           !f2.text.hasPrefix("0x1F") {
            throw CaseFailure(message: "hex prefix lost: \(f2.text)")
        }
        // A real multiplication still converts.
        guard let f3 = InputFormatting.formatLine("10x5", prefs: prefs) else {
            throw CaseFailure(message: "formatLine(10x5) returned nil")
        }
        try expectEqual(f3.text, "10 × 5")
    },
    EngineCase("r85-coordinate-copy-text") {
        // The location answer's copy text is the retypeable pair.
        let res = evalGeoLine(GeoQuery(kind: .location, key: "loc:london"),
                              geo: GeoContext(snapshots: ["london": r85London]),
                              decimalPlaces: 6, context: .legacy)
        guard case .location = res else {
            throw CaseFailure(message: "location result: \(res)")
        }
        let text = AnswerDisplay.text(for: res, decimalPlaces: 6, context: .legacy)
        try expectEqual(text, "51.5074° N, 0.1278° W")
    },
    EngineCase("r85-dms-copy-text") {
        let line = r85Sheet("156.742 as DMS")[0].result
        let text = AnswerDisplay.text(for: line, decimalPlaces: 6, context: .legacy)
        try expectEqual(text, "156° 44′ 31.2″")
    },
]
