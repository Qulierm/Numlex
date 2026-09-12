import Foundation
import NumlexCore

// MARK: - Bundled timezone catalog (temporal Task 3)

private func catalogDirectory() -> URL {
    guard let url = TimezoneCatalog.builtResourceDirectory else {
        return URL(fileURLWithPath: "/nonexistent/NumlexTimezones")
    }
    return url
}

private func loadedCatalog() throws -> TimezoneCatalog {
    try TimezoneCatalog(contentsOf: catalogDirectory())
}

public let timezoneCatalogCases: [EngineCase] = [

    EngineCase("timezone-catalog-loads-and-verifies-integrity") {
        let catalog = try loadedCatalog()
        // The FULL generated set, not fixtures.
        try expect(catalog.zones.count >= 300, "zones: \(catalog.zones.count)")
        try expect(catalog.aliases.count >= 200, "aliases: \(catalog.aliases.count)")
        try expect(catalog.cities.count >= 5000, "cities >= 100k: \(catalog.cities.count)")
        try expect(catalog.countries.count >= 150, "countries: \(catalog.countries.count)")
        try expect(catalog.airports.count >= 20000, "airport codes: \(catalog.airports.count)")
        try expect(!catalog.ianaVersion.isEmpty, "tzdata release pinned")
        // Every canonical zone is a real identifier Foundation can build —
        // otherwise the mapping would be unusable (fail closed at use).
        for zone in catalog.zones.prefix(40) {
            try expect(catalog.isAvailable(zone), "\(zone) is available")
        }
        // The embedded (process-wide) catalog resolves through the bundle.
        let shared = TimezoneCatalog.shared
        try expect(shared != nil, "the embedded catalog loads from the bundle")
        try expectEqual(shared?.zones.count, catalog.zones.count, "same zone count")
    },

    EngineCase("timezone-catalog-required-city-mappings") {
        let catalog = try loadedCatalog()
        let required: [(String, String)] = [
            ("Paris", "Europe/Paris"), ("Tokyo", "Asia/Tokyo"),
            ("Sydney", "Australia/Sydney"), ("Chicago", "America/Chicago"),
            ("Vancouver", "America/Vancouver"), ("Seattle", "America/Los_Angeles"),
            ("Moscow", "Europe/Moscow"),
        ]
        for (city, zone) in required {
            try expectEqual(catalog.zone(forCity: city), .zone(zone), "\(city) -> \(zone)")
            try expect(catalog.isAvailable(zone), "\(zone) is available")
        }
    },

    EngineCase("timezone-catalog-required-country-and-airport-mappings") {
        let catalog = try loadedCatalog()
        try expectEqual(catalog.zone(forCountry: "JP"), "Asia/Tokyo", "Japan")
        try expectEqual(catalog.zone(forCountry: "TH"), "Asia/Bangkok", "Thailand")
        try expectEqual(catalog.zone(forCountry: "jp"), "Asia/Tokyo", "lowercase country")
        try expectEqual(catalog.zone(forCountry: "ZZ"), nil, "unknown country fails closed")
        try expectEqual(catalog.zone(forAirportCode: "LAX"), "America/Los_Angeles", "LAX")
        try expectEqual(catalog.zone(forAirportCode: "lax"), "America/Los_Angeles",
                        "IATA is case-insensitive")
        try expectEqual(catalog.zone(forAirportCode: "KLAX"), "America/Los_Angeles",
                        "the ICAO form of LAX agrees")
        try expectEqual(catalog.zone(forAirportCode: "EGLL"), "Europe/London",
                        "a representative ICAO code")
        try expectEqual(catalog.zone(forAirportCode: "RJTT"), "Asia/Tokyo",
                        "a representative ICAO code outside the US")
        try expectEqual(catalog.zone(forAirportCode: "ZZZZ"), nil, "unknown code fails closed")
    },

    EngineCase("timezone-catalog-alias-and-normalization") {
        let catalog = try loadedCatalog()
        // A backward-compatibility alias canonicalizes to its target.
        try expectEqual(catalog.canonicalZone("US/Pacific"), "America/Los_Angeles",
                        "a tzdata alias resolves")
        try expectEqual(catalog.canonicalZone("America/Los_Angeles"),
                        "America/Los_Angeles", "the canonical id is kept")
        try expectEqual(catalog.canonicalZone("america/los_angeles"),
                        "America/Los_Angeles", "case-insensitive")
        try expectEqual(catalog.canonicalZone("Not/AZone"), nil, "unknown id fails closed")
        try expectEqual(catalog.isAvailable("Not/AZone"), false, "unavailable mapping")
        // City names normalize case, whitespace and diacritics.
        try expectEqual(catalog.zone(forCity: "  PARIS "), .zone("Europe/Paris"),
                        "case and whitespace")
        try expectEqual(catalog.zone(forCity: "Zürich"), .zone("Europe/Zurich"),
                        "a diacritic name")
        try expectEqual(catalog.zone(forCity: "Zuerich"), .zone("Europe/Zurich"),
                        "the ASCII spelling agrees")
        try expectEqual(catalog.zone(forCity: "   "), .unknown, "blank is unknown")
        try expectEqual(catalog.zone(forCity: "Nowhereville"), .unknown, "unknown city")
        // An explicit `City, CC` qualifier disambiguates.
        try expectEqual(catalog.zone(forCity: "Portland, US"), .zone("America/Los_Angeles"),
                        "a US qualifier picks the largest US city")
        try expectEqual(catalog.zone(forCity: "Portland, ZZ"), .unknown,
                        "an unknown qualifier fails closed")
    },

    EngineCase("timezone-catalog-ambiguity-policy-is-explicit") {
        func city(_ name: String, _ country: String, _ population: Int,
                  _ zone: String) -> TimezoneCatalog.City {
            TimezoneCatalog.City(name: name, asciiName: name, country: country,
                                 population: population, zone: zone)
        }
        // A unique largest population wins.
        try expectEqual(TimezoneCatalog.resolve(candidates: [
            city("Springfield", "US", 120_000, "America/Chicago"),
            city("Springfield", "US", 60_000, "America/New_York"),
        ]), .zone("America/Chicago"), "the larger population wins")
        // An exact tie is ambiguous — never a silent guess.
        if case .ambiguous(let candidates) = TimezoneCatalog.resolve(candidates: [
            city("Twinville", "US", 100_000, "America/Chicago"),
            city("Twinville", "CA", 100_000, "America/Toronto"),
        ]) {
            try expectEqual(candidates.count, 2, "both candidates reported")
        } else {
            throw CaseFailure(message: "an exact tie must be ambiguous", location: "TimezoneCatalog")
        }
        try expectEqual(TimezoneCatalog.resolve(candidates: []), .unknown,
                        "no candidates is unknown")
        // The name key folds diacritics and punctuation deterministically.
        try expectEqual(TimezoneCatalog.normalizedName("Zürich"), "zurich", "diacritics")
        try expectEqual(TimezoneCatalog.normalizedName("  San   José "), "san jose",
                        "whitespace and punctuation")
        try expectEqual(TimezoneCatalog.normalizedName("ST. LOUIS"), "st louis", "case and dot")
    },

    EngineCase("timezone-catalog-fails-closed-on-broken-resources") {
        let source = catalogDirectory()
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("numlex-tz-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        // A missing file is a load error, never a partially working catalog.
        do {
            _ = try TimezoneCatalog(contentsOf: temp)
            throw CaseFailure(message: "a missing resource must fail the load",
                              location: "TimezoneCatalog")
        } catch is TimezoneCatalog.LoadError {
            // expected
        }
        // Copy the real resources, then tamper one: the hash check refuses it.
        for name in ["iana-zones.tsv", "cities.tsv", "countries.tsv",
                     "airports.tsv", "sources.json"] {
            try FileManager.default.copyItem(at: source.appendingPathComponent(name),
                                             to: temp.appendingPathComponent(name))
        }
        _ = try TimezoneCatalog(contentsOf: temp)  // clean copy loads
        var tampered = try Data(contentsOf: temp.appendingPathComponent("cities.tsv"))
        tampered.append(contentsOf: Utf8("Paris\tParis\tFR\t2138551\tMars/Olympus\n"))
        try tampered.write(to: temp.appendingPathComponent("cities.tsv"))
        do {
            _ = try TimezoneCatalog(contentsOf: temp)
            throw CaseFailure(message: "a tampered resource must fail the load",
                              location: "TimezoneCatalog")
        } catch is TimezoneCatalog.LoadError {
            // expected
        }
    },

    EngineCase("timezone-resource-manifest-pins-source-and-licenses") {
        let manifest = catalogDirectory().appendingPathComponent("sources.json")
        let data = try Data(contentsOf: manifest)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CaseFailure(message: "sources.json parses", location: "TimezoneCatalog")
        }
        try expectEqual(json["generator"] as? String, "Scripts/generate-timezone-data.py",
                        "the committed generator is recorded")
        try expect((json["ianaVersion"] as? String)?.isEmpty == false, "a tzdata release is pinned")
        guard let sources = json["sources"] as? [String: [String: String]] else {
            throw CaseFailure(message: "sources recorded", location: "TimezoneCatalog")
        }
        for (name, meta) in sources {
            try expect(meta["url"]?.hasPrefix("https://") == true, "\(name): pinned URL")
            try expect(meta["sha256"]?.count == 64, "\(name): pinned hash")
            try expect(meta["license"]?.isEmpty == false, "\(name): license recorded")
            try expect(meta["attribution"]?.isEmpty == false, "\(name): attribution recorded")
        }
        try expectEqual(json["minPopulation"] as? Int, 100_000, "the population threshold")
        // The attribution file ships beside the data.
        let attribution = catalogDirectory().appendingPathComponent("ATTRIBUTION.md")
        let text = String(decoding: try Data(contentsOf: attribution), as: UTF8.self)
        try expect(text.contains("GeoNames"), "GeoNames attributed")
        try expect(text.contains("CC BY 4.0"), "the CC BY license is named")
        try expect(text.contains("IANA"), "IANA attributed")
        try expect(text.contains("MIT"), "the MIT license is named")
    }
]

private func Utf8(_ text: String) -> Data { Data(text.utf8) }
