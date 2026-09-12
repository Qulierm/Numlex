import CryptoKit
import Foundation

// MARK: - BLS CPI-U catalog (Package 2, Task 5)
//
// The versioned `cpi-u-2026.1` bundle: the official BLS CPI-U All Items
// annual averages (1982-84=100) from 1913 through the latest COMPLETE
// year, plus an explicitly PROVISIONAL 2026 YTD average of the official
// monthly observations (the manifest records the included months, the
// latest observation and the snapshot date — no annual average is
// fabricated). Generated reproducibly by `Scripts/generate-cpi-data.py`
// from the BLS public API; the loader verifies the recorded SHA-256 and
// fails closed. Runtime is fully offline and deterministic: the
// "today" index is the bundle's snapshot index, never the wall clock.

public struct CPICatalog: Sendable, Equatable {

    public enum LoadError: Error, Equatable {
        case missingResource(String)
        case integrityFailure(String)
        case malformed(String)
    }

    public struct Provisional: Equatable, Sendable {
        public let year: Int
        public let months: [Int]
        public let monthly: [Int: Double]
        public let ytdAverage: Double
        public let latestMonth: Int
        public let latestValue: Double
        public let method: String
    }

    public let version: String
    public let snapshotDate: String
    public let series: String
    public let sourceTitle: String
    public let sourceURL: String
    public let basePeriod: String
    public let annual: [Int: Double]
    public let provisional: Provisional?
    public let latestAnnualYear: Int
    public let latestSnapshotYear: Int
    public let latestSnapshotIndex: Double

    public static let shared: CPICatalog? = CPICatalog.embedded()

    // MARK: loading

    public static func embedded() -> CPICatalog? {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let directory = bundle.url(forResource: "NumlexCPI", withExtension: nil)
                ?? bundle.resourceURL?.appendingPathComponent("NumlexCPI") else {
            return nil
        }
        return try? CPICatalog(contentsOf: directory)
    }

    public static var builtResourceDirectory: URL? {
        let candidates = [
            Bundle.main.resourceURL,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/arm64-apple-macosx/debug"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/debug"),
        ]
        for base in candidates {
            guard let base else { continue }
            let direct = base.appendingPathComponent("NumlexCPI")
            if FileManager.default.fileExists(atPath: direct.path) { return direct }
            let nested = base.appendingPathComponent("Numlex_NumlexCore.bundle")
                .appendingPathComponent("NumlexCPI")
            if FileManager.default.fileExists(atPath: nested.path) { return nested }
        }
        return nil
    }

    public init(contentsOf directory: URL) throws {
        let dataURL = directory.appendingPathComponent("cpi-u.json")
        let manifestURL = directory.appendingPathComponent("sources.json")
        guard let data = try? Data(contentsOf: dataURL) else {
            throw LoadError.missingResource("cpi-u.json")
        }
        guard let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any] else {
            throw LoadError.missingResource("sources.json")
        }
        let resources = manifest["resources"] as? [String: [String: String]]
        guard let expected = resources?["cpi-u.json"]?["sha256"] else {
            throw LoadError.integrityFailure("cpi-u.json")
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == expected else { throw LoadError.integrityFailure("cpi-u.json") }
        guard let decoded = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw LoadError.malformed("cpi-u.json")
        }
        version = decoded.version
        snapshotDate = decoded.snapshotDate
        series = decoded.series
        sourceTitle = decoded.source.title
        sourceURL = decoded.source.url
        basePeriod = decoded.basePeriod
        var annualTable: [Int: Double] = [:]
        for (key, value) in decoded.annual {
            guard let year = Int(key), value.isFinite, value > 0 else {
                throw LoadError.malformed("annual.\(key)")
            }
            annualTable[year] = value
        }
        guard !annualTable.isEmpty else { throw LoadError.malformed("annual") }
        // CONTINUOUS coverage contract: every integer year from 1913
        // through the latest complete year must exist (a gap would make
        // min/max coverage claims false).
        let firstYear = 1913
        guard let lastYear = annualTable.keys.max(),
              Set(annualTable.keys) == Set(firstYear...lastYear),
              manifest["annualCoverage"] as? [Int] == [firstYear, lastYear] else {
            throw LoadError.malformed("annualCoverage")
        }
        annual = annualTable
        provisional = decoded.provisional.map { p in
            Provisional(year: p.year, months: p.months,
                        monthly: Dictionary(uniqueKeysWithValues: p.monthly.map {
                            (Int($0.key) ?? 0, $0.value)
                        }),
                        ytdAverage: p.ytdAverage, latestMonth: p.latestMonth,
                        latestValue: p.latestValue, method: p.method)
        }
        latestAnnualYear = decoded.latestAnnualYear
        latestSnapshotYear = decoded.latestSnapshotYear
        latestSnapshotIndex = decoded.latestSnapshotIndex
        guard latestSnapshotIndex.isFinite, latestSnapshotIndex > 0 else {
            throw LoadError.malformed("latestSnapshotIndex")
        }
    }

    /// A testable in-memory catalog.
    public init(version: String, snapshotDate: String, series: String,
                sourceTitle: String, sourceURL: String, basePeriod: String,
                annual: [Int: Double], provisional: Provisional?,
                latestAnnualYear: Int, latestSnapshotYear: Int,
                latestSnapshotIndex: Double) {
        self.version = version
        self.snapshotDate = snapshotDate
        self.series = series
        self.sourceTitle = sourceTitle
        self.sourceURL = sourceURL
        self.basePeriod = basePeriod
        self.annual = annual
        self.provisional = provisional
        self.latestAnnualYear = latestAnnualYear
        self.latestSnapshotYear = latestSnapshotYear
        self.latestSnapshotIndex = latestSnapshotIndex
    }

    // MARK: lookup

    /// The index for a year: an annual average, or the provisional YTD
    /// for the provisional year. nil = outside the table.
    public func index(for year: Int) -> Double? {
        if let value = annual[year] { return value }
        if let provisional, provisional.year == year { return provisional.ytdAverage }
        return nil
    }

    /// True when the year is inside the generated coverage (the annual
    /// table or the provisional entry).
    public func isSupported(_ year: Int) -> Bool {
        index(for: year) != nil
    }

    // MARK: payload decoding

    private struct Payload: Decodable {
        let version: String
        let snapshotDate: String
        let series: String
        let basePeriod: String
        let source: Source
        let annual: [String: Double]
        let provisional: ProvisionalPayload?
        let latestAnnualYear: Int
        let latestSnapshotYear: Int
        let latestSnapshotIndex: Double

        struct Source: Decodable {
            let title: String
            let url: String
        }
        struct ProvisionalPayload: Decodable {
            let year: Int
            let months: [Int]
            let monthly: [String: Double]
            let ytdAverage: Double
            let latestMonth: Int
            let latestValue: Double
            let method: String
        }
    }
}
