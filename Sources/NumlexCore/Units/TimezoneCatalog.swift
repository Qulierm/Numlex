import CryptoKit
import Foundation

/// The bundled offline timezone catalog: canonical IANA identifiers and their
/// aliases, cities with population >= 100,000, country -> capital zone and
/// IATA/ICAO -> zone. Everything is generated reproducibly by
/// `Scripts/generate-timezone-data.py` and committed under
/// `Resources/NumlexTimezones`; nothing here touches the network.
///
/// The catalog FAILS CLOSED: missing files, a tampered hash, an unknown city,
/// country, code or zone all resolve to nil (or an explicit ambiguity), and a
/// mapped identifier Foundation cannot instantiate is treated as unavailable.
public struct TimezoneCatalog: Sendable {

    public struct City: Equatable, Sendable {
        public let name: String
        public let asciiName: String
        public let country: String
        public let population: Int
        public let zone: String

        public init(name: String, asciiName: String, country: String,
                    population: Int, zone: String) {
            self.name = name
            self.asciiName = asciiName
            self.country = country
            self.population = population
            self.zone = zone
        }
    }

    public enum LoadError: Error, Equatable {
        case missingResource(String)
        case integrityFailure(String)
    }

    /// The result of a city lookup: one zone, or the candidates that share a
    /// name and cannot be separated by the documented policy.
    public enum CityLookup: Equatable, Sendable {
        case zone(String)
        case ambiguous([City])
        case unknown
    }

    public let ianaVersion: String
    public let zones: [String]
    public let aliases: [String: String]
    public let cities: [City]
    public let countries: [String: String]
    public let airports: [String: String]

    /// The process-wide catalog, loaded once (nil when the bundle is broken —
    /// every lookup then fails closed).
    public static let shared: TimezoneCatalog? = TimezoneCatalog.embedded()

    // MARK: loading

    /// Loads the catalog from the SwiftPM resource bundle with a full
    /// integrity check (required files present + recorded SHA-256).
    public static func embedded() -> TimezoneCatalog? {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let directory = bundle.url(forResource: "NumlexTimezones", withExtension: nil)
                ?? bundle.resourceURL?.appendingPathComponent("NumlexTimezones") else {
            return nil
        }
        return try? TimezoneCatalog(contentsOf: directory)
    }

    /// The committed resource directory as it exists in the build products
    /// (used by the tests; `embedded()` uses the SwiftPM bundle accessor).
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
            let direct = base.appendingPathComponent("NumlexTimezones")
            if FileManager.default.fileExists(atPath: direct.path) { return direct }
            let nested = base.appendingPathComponent("Numlex_NumlexCore.bundle")
                .appendingPathComponent("NumlexTimezones")
            if FileManager.default.fileExists(atPath: nested.path) { return nested }
        }
        return nil
    }

    /// Testable loader: verifies the resources in `directory` and parses them.
    public init(contentsOf directory: URL) throws {
        let required = ["iana-zones.tsv", "cities.tsv", "countries.tsv",
                        "airports.tsv", "sources.json"]
        var files: [String: Data] = [:]
        for name in required {
            let url = directory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else {
                throw LoadError.missingResource(name)
            }
            files[name] = data
        }
        // Integrity: the committed hash of every resource must match the
        // manifest, so a truncated or edited file can never load.
        guard let manifest = try? JSONSerialization.jsonObject(with: files["sources.json"]!)
                as? [String: Any],
              let recorded = manifest["resources"] as? [String: [String: String]] else {
            throw LoadError.integrityFailure("sources.json")
        }
        for (name, meta) in recorded {
            guard let expected = meta["sha256"], let data = files[name] else {
                throw LoadError.integrityFailure(name)
            }
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard digest == expected else { throw LoadError.integrityFailure(name) }
        }
        ianaVersion = manifest["ianaVersion"] as? String ?? "unknown"

        func lines(_ name: String) -> [String] {
            String(decoding: files[name]!, as: UTF8.self)
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map(String.init)
        }
        var zones: [String] = []
        var aliases: [String: String] = [:]
        for line in lines("iana-zones.tsv") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard let zone = fields.first.map(String.init), !zone.isEmpty else { continue }
            zones.append(zone)
            guard fields.count > 2 else { continue }
            for alias in fields[2].split(separator: ",") {
                aliases[String(alias)] = zone
            }
        }
        self.zones = zones
        self.aliases = aliases

        var cities: [City] = []
        for line in lines("cities.tsv") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 5, let population = Int(fields[3]) else { continue }
            cities.append(City(name: String(fields[0]), asciiName: String(fields[1]),
                               country: String(fields[2]), population: population,
                               zone: String(fields[4])))
        }
        self.cities = cities

        var countries: [String: String] = [:]
        for line in lines("countries.tsv") {
            let fields = line.split(separator: "\t")
            guard fields.count >= 2 else { continue }
            countries[String(fields[0]).uppercased()] = String(fields[1])
        }
        self.countries = countries

        var airports: [String: String] = [:]
        for line in lines("airports.tsv") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 3 else { continue }
            let zone = String(fields[2])
            let iata = String(fields[0]).uppercased()
            let icao = String(fields[1]).uppercased()
            if !iata.isEmpty { airports[iata] = zone }
            if !icao.isEmpty { airports[icao] = zone }
        }
        self.airports = airports
    }

    // MARK: lookup

    /// A city zone. The documented ambiguity policy: a name resolves only
    /// when the largest population is STRICTLY greater than every other
    /// candidate; an exact tie is ambiguous (never a silent guess). A
    /// `City, CC` qualifier disambiguates explicitly.
    public func zone(forCity raw: String) -> CityLookup {
        let text = raw.trimmingCharacters(in: .whitespaces)
        var qualifier: String?
        if let comma = text.lastIndex(of: ",") {
            qualifier = String(text[text.index(after: comma)...])
                .trimmingCharacters(in: .whitespaces).uppercased()
        }
        let name = qualifier == nil ? text : String(text[..<text.lastIndex(of: ",")!])
        let key = TimezoneCatalog.normalizedName(name)
        guard !key.isEmpty else { return .unknown }
        let matches = cities.filter {
            TimezoneCatalog.normalizedName($0.name) == key
                || TimezoneCatalog.normalizedName($0.asciiName) == key
        }
        let candidates = qualifier.map { q in matches.filter { $0.country == q } } ?? matches
        return TimezoneCatalog.resolve(candidates: candidates)
    }

    /// The PURE ambiguity policy (testable without the bundle): the largest
    /// population wins only when it is STRICTLY greater than every other
    /// candidate; an exact tie is ambiguous, never a silent guess.
    public static func resolve(candidates: [City]) -> CityLookup {
        let sorted = candidates.sorted {
            $0.population != $1.population ? $0.population > $1.population
                : ($0.country, $0.zone) < ($1.country, $1.zone)
        }
        guard let best = sorted.first else { return .unknown }
        if sorted.count > 1, sorted[1].population == best.population {
            return .ambiguous(sorted)
        }
        return .zone(best.zone)
    }

    public func zone(forCountry code: String) -> String? {
        countries[code.trimmingCharacters(in: .whitespaces).uppercased()]
    }

    /// IATA (3 letters) or ICAO (4 letters) airport code.
    public func zone(forAirportCode code: String) -> String? {
        airports[code.trimmingCharacters(in: .whitespaces).uppercased()]
    }

    /// Canonicalizes an IANA identifier (alias or canonical), case-insensitively.
    public func canonicalZone(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        if zones.contains(text) { return text }
        if let target = aliases[text] { return target }
        let folded = text.lowercased()
        if let zone = zones.first(where: { $0.lowercased() == folded }) { return zone }
        if let alias = aliases.first(where: { $0.key.lowercased() == folded }) {
            return alias.value
        }
        return nil
    }

    /// True only when the identifier is canonical AND Foundation can build it
    /// (the fail-closed rule for an unavailable mapping).
    public func isAvailable(_ identifier: String) -> Bool {
        guard let zone = canonicalZone(identifier) else { return false }
        return TimeZone(identifier: zone) != nil
    }

    /// Safe name key: lowercased, diacritics folded, punctuation removed,
    /// whitespace collapsed.
    public static func normalizedName(_ raw: String) -> String {
        let folded = raw.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                 locale: Locale(identifier: "en_US_POSIX"))
        var out = ""
        var lastSpace = false
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                out.unicodeScalars.append(scalar)
                lastSpace = false
            } else if !lastSpace, !out.isEmpty {
                out.append(" ")
                lastSpace = true
            }
        }
        while out.hasSuffix(" ") { out.removeLast() }
        return out
    }
}
