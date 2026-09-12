import CryptoKit
import Foundation

// MARK: - Estimated income-tax catalog (Package 2, Task 4)
//
// The versioned `income-tax-2026.1` bundle: progressive national
// brackets for a single individual over the taxable amount (the
// basic zero-rate allowance / standard deduction is a 0% bracket), the
// table currency, the applicable tax year, official source title/URL
// and an explicit model note. Everything is generated reproducibly by
// `Scripts/generate-income-tax-data.py`; the loader verifies the
// recorded SHA-256 and fails closed. Runtime is fully offline and no
// value is ever invented at runtime.

public struct IncomeTaxCatalog: Sendable, Equatable {

    public enum LoadError: Error, Equatable {
        case missingResource(String)
        case integrityFailure(String)
        case malformed(String)
    }

    public struct Bracket: Equatable, Sendable {
        /// The inclusive upper bound of the slice; nil = open-ended.
        public let upTo: Double?
        /// The marginal rate as a fraction (0.22 = 22%).
        public let rate: Double
        public init(upTo: Double?, rate: Double) {
            self.upTo = upTo
            self.rate = rate
        }
    }

    public struct Table: Equatable, Sendable {
        public let country: String
        public let aliases: [String]
        public let currency: String
        public let taxYear: Int
        /// The honest fiscal period (`2026`, `2026/27`, `2026 (income
        /// 2025)`, `AY 2026-27 (FY 2025-26)`, ...) — an Int cannot
        /// always describe applicability.
        public let taxPeriod: String
        public let brackets: [Bracket]
        public let sourceTitle: String
        public let sourceURL: String
        public let note: String

        public init(country: String, aliases: [String], currency: String,
                    taxYear: Int, taxPeriod: String, brackets: [Bracket],
                    sourceTitle: String, sourceURL: String, note: String) {
            self.country = country
            self.aliases = aliases
            self.currency = currency
            self.taxYear = taxYear
            self.taxPeriod = taxPeriod
            self.brackets = brackets
            self.sourceTitle = sourceTitle
            self.sourceURL = sourceURL
            self.note = note
        }

        /// Pure progressive calculation: every bracket taxes its own
        /// slice of the taxable amount. Deterministic, no rounding.
        public func tax(on income: Double) -> Double {
            guard income.isFinite, income > 0 else { return 0 }
            var lower = 0.0
            var tax = 0.0
            for bracket in brackets {
                let upper = bracket.upTo ?? .infinity
                guard upper > lower else { continue }
                let slice = min(income, upper) - lower
                if slice > 0 { tax += slice * bracket.rate }
                lower = upper
                if income <= upper { break }
            }
            return tax.isFinite ? tax : 0
        }
    }

    public let version: String
    public let snapshotDate: String
    public let model: String
    public let tables: [Table]

    public static let shared: IncomeTaxCatalog? = IncomeTaxCatalog.embedded()

    // MARK: loading

    public static func embedded() -> IncomeTaxCatalog? {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let directory = bundle.url(forResource: "NumlexIncomeTax", withExtension: nil)
                ?? bundle.resourceURL?.appendingPathComponent("NumlexIncomeTax") else {
            return nil
        }
        return try? IncomeTaxCatalog(contentsOf: directory)
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
            let direct = base.appendingPathComponent("NumlexIncomeTax")
            if FileManager.default.fileExists(atPath: direct.path) { return direct }
            let nested = base.appendingPathComponent("Numlex_NumlexCore.bundle")
                .appendingPathComponent("NumlexIncomeTax")
            if FileManager.default.fileExists(atPath: nested.path) { return nested }
        }
        return nil
    }

    public init(contentsOf directory: URL) throws {
        let dataURL = directory.appendingPathComponent("income-tax.json")
        let manifestURL = directory.appendingPathComponent("sources.json")
        guard let data = try? Data(contentsOf: dataURL) else {
            throw LoadError.missingResource("income-tax.json")
        }
        guard let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any] else {
            throw LoadError.missingResource("sources.json")
        }
        let resources = manifest["resources"] as? [String: [String: String]]
        guard let expected = resources?["income-tax.json"]?["sha256"] else {
            throw LoadError.integrityFailure("income-tax.json")
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == expected else { throw LoadError.integrityFailure("income-tax.json") }
        guard let decoded = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw LoadError.malformed("income-tax.json")
        }
        version = decoded.version
        snapshotDate = decoded.snapshotDate
        model = decoded.model
        tables = decoded.countries.map { entry in
            Table(country: entry.country.uppercased(),
                  aliases: entry.aliases,
                  currency: entry.currency.uppercased(),
                  taxYear: entry.taxYear,
                  taxPeriod: entry.taxPeriod ?? String(entry.taxYear),
                  brackets: entry.brackets.map { Bracket(upTo: $0.upTo, rate: $0.rate) },
                  sourceTitle: entry.source.title,
                  sourceURL: entry.source.url,
                  note: entry.note)
        }
        guard !tables.isEmpty else { throw LoadError.malformed("countries") }
    }

    /// A testable in-memory catalog.
    public init(version: String, snapshotDate: String, model: String,
                tables: [Table]) {
        self.version = version
        self.snapshotDate = snapshotDate
        self.model = model
        self.tables = tables
    }

    // MARK: lookup

    /// Case-insensitive country/alias lookup (`us`, `USA`, `United
    /// States` all resolve to the US table).
    public func table(for country: String) -> Table? {
        let key = country.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        for table in tables {
            if table.country.lowercased() == key { return table }
            for alias in table.aliases where alias.lowercased() == key {
                return table
            }
        }
        return nil
    }

    // MARK: payload decoding

    private struct Payload: Decodable {
        let version: String
        let snapshotDate: String
        let model: String
        let countries: [Entry]

        struct Entry: Decodable {
            let country: String
            let aliases: [String]
            let currency: String
            let taxYear: Int
            let taxPeriod: String?
            let brackets: [BracketEntry]
            let source: Source
            let note: String
        }
        struct BracketEntry: Decodable {
            let upTo: Double?
            let rate: Double
        }
        struct Source: Decodable {
            let title: String
            let url: String
        }
    }
}
