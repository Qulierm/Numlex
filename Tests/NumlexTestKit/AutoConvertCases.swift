import Foundation
import NumlexCore

/// Numbers ▸ Auto-convert single units: the strict stand-alone-quantity
/// eligibility, the deterministic metric/US/UK targets, the evaluation
/// context wiring and the persistence of the preference.
private func autoConvertSource(_ relativePath: String) -> String? {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // NumlexTestKit
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repository root
    let url = root.appendingPathComponent(relativePath).standardizedFileURL
    return try? String(contentsOf: url, encoding: .utf8)
}

private let autoConvertKeys = [
    "numbers.autoConvert", "numbers.autoConvertCap",
    "numbers.autoConvert.off", "numbers.autoConvert.localUnits"
]

/// One evaluated line under a local-unit system (nil = Off), through the
/// PUBLIC single-line entry point every caller shares.
private func autoConvertEval(_ line: String,
                             _ system: LocalUnitSystem?,
                             unitContext: UnitContext = .builtIns) -> LineResult? {
    var variables: [String: Double] = [:]
    return evalLine(line, variables: &variables, rates: Rates(),
                    decimalPlaces: 7, now: Date(timeIntervalSince1970: 1_700_000_000),
                    calendar: Calendar(identifier: .gregorian),
                    unitContext: unitContext, localUnits: system)
}

private func autoConvertNumber(_ line: String,
                               _ system: LocalUnitSystem?) throws -> (value: Double, unit: String?) {
    guard let result = autoConvertEval(line, system) else {
        throw CaseFailure(message: "no result for \(line)")
    }
    if case .number(let v, let unit, _, _) = result { return (v, unit) }
    throw CaseFailure(message: "not a number: \(line) -> \(result)")
}

/// The unit label of a target chosen by the pure policy.
private func autoConvertTargetLabel(_ family: LocalUnitConversion.Family,
                                    _ system: LocalUnitSystem,
                                    _ base: Double) throws -> String {
    guard let label = LocalUnitConversion.targetLabel(for: family, system: system,
                                                      baseMagnitude: base) else {
        throw CaseFailure(message: "no target for \(family)/\(system)")
    }
    return label
}

public let autoConvertCases: [EngineCase] = [
    EngineCase("auto-convert-off-is-byte-for-byte-the-old-behavior") {
        // Off (nil) must return exactly what the engine returned before:
        // the typed unit, untouched by any conversion.
        for (line, value, unit) in [("3 km", 3.0, "km"), ("5 kg", 5.0, "kg"),
                                    ("2 mi", 2.0, "mi"), ("1 gal", 1.0, "gal"),
                                    ("100 kPa", 100.0, "kPa"), ("2 kg", 2.0, "kg")] {
            let off = try autoConvertNumber(line, nil)
            try expectClose(off.value, value, 1e-9, "\(line) unchanged when Off")
            try expectEqual(off.unit, unit, "\(line) unit unchanged when Off")
        }
        // The default preference is Off and its resolved context is nil
        // for every measurement system.
        try expectEqual(AppSettings.defaults.autoConvertUnits, .off)
        try expectEqual(AppSettings.defaults.localUnitSystem(measurementSystem: .metric), nil)
        try expectEqual(AppSettings.defaults.localUnitSystem(measurementSystem: .us), nil)
        try expectEqual(AppSettings.defaults.localUnitSystem(measurementSystem: .uk), nil)
    },
    EngineCase("auto-convert-us-examples") {
        // The two supplied examples.
        let km = try autoConvertNumber("3 km", .us)
        try expectEqual(km.unit, "mi")
        try expectClose(km.value, 1.8641135767120018, 1e-6, "3 km ≈ 1.86 mi")
        let kg = try autoConvertNumber("5 kg", .us)
        try expectEqual(kg.unit, "lb")
        try expectClose(kg.value, 11.023113109243879, 1e-6, "5 kg ≈ 11.02 lb")
        // Length: sub-foot lengths become inches, larger ones feet/miles.
        try expectEqual(try autoConvertNumber("100 m", .us).unit, "ft")
        try expectEqual(try autoConvertNumber("0.2 m", .us).unit, "in")
        try expectEqual(try autoConvertNumber("5000 m", .us).unit, "mi")
        // Mass: below one pound → ounces.
        try expectEqual(try autoConvertNumber("4 oz", .us).unit, "oz")
        try expectEqual(try autoConvertNumber("2 kg", .us).unit, "lb")
        try expectEqual(try autoConvertNumber("0.2 kg", .us).unit, "oz")
        // Volume: below a gallon → US fluid ounces.
        let flOz = try autoConvertNumber("0.5 L", .us)
        try expectEqual(flOz.unit, "fl oz")
        try expectClose(flOz.value, 16.907011350921495, 1e-6, "0.5 L ≈ 16.9 fl oz")
        let gal = try autoConvertNumber("4 L", .us)
        try expectEqual(gal.unit, "gal")
        try expectClose(gal.value, 1.0566882094325938, 1e-6, "4 L ≈ 1.06 gal")
        // Area, speed, acceleration, pressure, density.
        let sqIn = try autoConvertNumber("0.001 m²", .us)
        try expectEqual(sqIn.unit, "in²")
        try expectClose(sqIn.value, 1.5500031000062, 1e-6, "1 cm² ≈ 1.55 in²")
        try expectEqual(try autoConvertNumber("1 m²", .us).unit, "ft²")
        try expectEqual(try autoConvertNumber("4000000 m²", .us).unit, "mi²")
        try expectClose(try autoConvertNumber("100 km/h", .us).value,
                        62.13711922373339, 1e-6, "100 km/h ≈ 62.14 mph")
        try expectClose(try autoConvertNumber("5 m/s²", .us).value,
                        16.404199475065617, 1e-6, "5 m/s² ≈ 16.4 ft/s²")
        try expectClose(try autoConvertNumber("100 kPa", .us).value,
                        14.503773773020923, 1e-6, "100 kPa ≈ 14.5 psi")
        try expectClose(try autoConvertNumber("1000 kg/m³", .us).value,
                        62.42796203356101, 1e-6, "1000 kg/m³ ≈ 62.4 lb/ft³")
    },
    EngineCase("auto-convert-metric-and-uk-targets") {
        // Metric: imperial and metric inputs land on the metric ladder.
        let mi = try autoConvertNumber("3 mi", .metric)
        try expectEqual(mi.unit, "km")
        try expectClose(mi.value, 4.828032, 1e-6, "3 mi = 4.83 km")
        try expectEqual(try autoConvertNumber("6 ft", .metric).unit, "m")
        try expectEqual(try autoConvertNumber("2 ft", .metric).unit, "cm")
        try expectEqual(try autoConvertNumber("0.5 in", .metric).unit, "cm")
        try expectEqual(try autoConvertNumber("0.1 in", .metric).unit, "mm")
        try expectEqual(try autoConvertNumber("2 lb", .metric).unit, "g")
        try expectEqual(try autoConvertNumber("5 lb", .metric).unit, "kg")
        try expectEqual(try autoConvertNumber("2 gal", .metric).unit, "L")
        try expectEqual(try autoConvertNumber("2 fl oz", .metric).unit, "ml")
        try expectEqual(try autoConvertNumber("10 ft²", .metric).unit, "m²")
        try expectEqual(try autoConvertNumber("100 mi²", .metric).unit, "km²")
        try expectEqual(try autoConvertNumber("60 mph", .metric).unit, "km/h")
        try expectEqual(try autoConvertNumber("20 ft/s²", .metric).unit, "m/s²")
        try expectEqual(try autoConvertNumber("14.5 psi", .metric).unit, "kPa")
        try expectEqual(try autoConvertNumber("100 lb/ft³", .metric).unit, "kg/m³")
        try expectEqual(try autoConvertNumber("5 m/s", .metric).unit, "km/h")

        // UK: short lengths metric, long distances miles, volume uses the
        // imperial gallon, acceleration and pressure stay metric.
        try expectEqual(try autoConvertNumber("0.5 m", .uk).unit, "cm")
        try expectEqual(try autoConvertNumber("3 m", .uk).unit, "m")
        try expectEqual(try autoConvertNumber("1 km", .uk).unit, "m")
        try expectEqual(try autoConvertNumber("3 km", .uk).unit, "mi")
        try expectEqual(try autoConvertNumber("2 kg", .uk).unit, "kg")
        try expectEqual(try autoConvertNumber("0.5 kg", .uk).unit, "g")
        try expectEqual(try autoConvertNumber("0.5 L", .uk).unit, "uk fl oz")
        try expectEqual(try autoConvertNumber("4 L", .uk).unit, "uk fl oz")
        try expectEqual(try autoConvertNumber("5 L", .uk).unit, "uk gal")
        try expectEqual(try autoConvertNumber("100 km/h", .uk).unit, "mph")
        try expectEqual(try autoConvertNumber("5 m/s²", .uk).unit, "m/s²")
        try expectEqual(try autoConvertNumber("100 kPa", .uk).unit, "kPa")
        try expectEqual(try autoConvertNumber("1000 kg/m³", .uk).unit, "kg/m³")
    },
    EngineCase("auto-convert-boundaries-already-local-and-signed") {
        // Threshold boundaries choose exactly one side (documented and
        // deterministic).
        try expectEqual(try autoConvertNumber("1 m", .metric).unit, "m")
        try expectEqual(try autoConvertNumber("0.99 m", .metric).unit, "cm")
        try expectEqual(try autoConvertNumber("0.009 m", .metric).unit, "mm")
        try expectEqual(try autoConvertNumber("999 m", .metric).unit, "m")
        try expectEqual(try autoConvertNumber("1000 m", .metric).unit, "km")
        try expectEqual(try autoConvertNumber("1 kg", .metric).unit, "kg")
        try expectEqual(try autoConvertNumber("0.5 kg", .metric).unit, "g")
        try expectEqual(try autoConvertNumber("1 L", .metric).unit, "L")
        try expectEqual(try autoConvertNumber("0.5 L", .metric).unit, "ml")
        // Already-local values are identity: value AND unit survive with
        // no floating round-trip.
        let local = try autoConvertNumber("3 km", .metric)
        try expectEqual(local.unit, "km")
        try expectClose(local.value, 3, 1e-12, "no floating round-trip")
        let localUs = try autoConvertNumber("3 mi", .us)
        try expectEqual(localUs.unit, "mi")
        try expectClose(localUs.value, 3, 1e-12)
        try expectEqual(try autoConvertNumber("5 m/s²", .metric).unit, "m/s²")
        // A single signed literal keeps its sign; zero keeps the smaller
        // unit of its family.
        let negative = try autoConvertNumber("-5 kg", .us)
        try expectEqual(negative.unit, "lb")
        try expectClose(negative.value, -11.023113109243879, 1e-6, "signed magnitude")
        try expectEqual(try autoConvertNumber("0 kg", .us).unit, "oz")
    },
    EngineCase("auto-convert-exclusions") {
        // Every exclusion keeps the ORIGINAL result.
        func expectUntouched(_ line: String, _ system: LocalUnitSystem, _ unit: String) throws {
            let r = try autoConvertNumber(line, system)
            try expectEqual(r.unit, unit, "\(line) must keep its unit")
        }
        try expectUntouched("x = 5 kg", .us, "kg")            // assignment
        try expectUntouched("5 kg + 2 kg", .us, "kg")         // arithmetic
        try expectUntouched("5 kg to lb", .us, "lb")          // explicit target
        try expectUntouched("5 kg * 2", .us, "kg")            // scalar product
        try expectUntouched("10 km / 2 h", .us, "km/h")       // compound rate
        try expectUntouched("1 h", .us, "h")                  // time
        try expectUntouched("30 °", .us, "deg")               // angle
        try expectUntouched("5 MB", .us, "MB")                // data
        try expectUntouched("500 kJ", .us, "kJ")              // energy
        try expectUntouched("2 kW", .us, "kW")                // power
        if case .money(_, let code)? = autoConvertEval("$5", .us) {
            try expectEqual(code, "USD", "money is never auto-converted")
        } else {
            throw CaseFailure(message: "money line no longer evaluates to money")
        }
        // A named value is never a stand-alone quantity: the assignment
        // and every later reference to it keep the typed unit.
        let sheet = resolveSheet(content: "distance = 5 km\ndistance * 2",
                                 lineIDs: [UUID(), UUID()], references: [],
                                 rates: Rates(), decimalPlaces: 7,
                                 now: Date(timeIntervalSince1970: 1_700_000_000),
                                 calendar: Calendar(identifier: .gregorian),
                                 localUnits: .us)
        try expectEqual(sheet.lines.count, 2)
        for row in sheet.lines {
            guard case .number(_, let unit, _, _) = row.result else {
                throw CaseFailure(message: "row \(row.sourceLineIndex) is not a number")
            }
            try expectEqual(unit, "km", "named values keep their own unit")
        }
        // A token line is never a stand-alone quantity.
        let tokenLine = "\(answerTokenMarker) + 2"
        if case .number(_, let unit, _, _)? = autoConvertEval(tokenLine, .us) {
            throw CaseFailure(message: "a token line must never be auto-converted: \(unit ?? "nil")")
        }
    },
    EngineCase("auto-convert-temperature-and-fuel-literals-stay-unit-less") {
        // Bare temperature and fuel-economy literals are NOT physical-unit
        // results in this engine: they evaluate to a plain number (their
        // conversion exists only through an explicit `to`/`in` phrase).
        // Auto-conversion therefore leaves them exactly as they are —
        // pinned here so a future engine change is a conscious one.
        for line in ["20 C", "20 celsius", "68 F", "20 kelvin", "20 rankine",
                     "8 L/100km", "30 US mpg", "12 UK mpg"] {
            for system in [LocalUnitSystem?.none, .metric, .us, .uk] {
                guard case .number(_, let unit, _, _)? = autoConvertEval(line, system) else {
                    continue
                }
                try expectEqual(unit, nil, "\(line) stays unit-less")
            }
        }
        // …while the explicit phrase keeps working and is never rewritten.
        let explicit = try autoConvertNumber("20 C to F", .us)
        try expectEqual(explicit.unit, "F°")
        try expectClose(explicit.value, 68, 1e-9, "explicit conversion unchanged")
    },
    EngineCase("auto-convert-target-policy-is-deterministic-and-injectable") {
        // The pure policy owns every family/system pair — including the
        // temperature and fuel rows, which this engine's stand-alone
        // literals cannot reach but which stay part of the contract.
        try expectEqual(try autoConvertTargetLabel(.length, .metric, 0.005), "mm")
        try expectEqual(try autoConvertTargetLabel(.length, .metric, 0.5), "cm")
        try expectEqual(try autoConvertTargetLabel(.length, .metric, 5), "m")
        try expectEqual(try autoConvertTargetLabel(.length, .metric, 5000), "km")
        try expectEqual(try autoConvertTargetLabel(.length, .us, 0.1), "in")
        try expectEqual(try autoConvertTargetLabel(.length, .us, 100), "ft")
        try expectEqual(try autoConvertTargetLabel(.length, .us, 1_000_000), "mi")
        try expectEqual(try autoConvertTargetLabel(.length, .uk, 0.5), "cm")
        try expectEqual(try autoConvertTargetLabel(.length, .uk, 100), "m")
        try expectEqual(try autoConvertTargetLabel(.length, .uk, 1_000_000), "mi")
        try expectEqual(try autoConvertTargetLabel(.mass, .metric, 0.5), "g")
        try expectEqual(try autoConvertTargetLabel(.mass, .metric, 5), "kg")
        try expectEqual(try autoConvertTargetLabel(.mass, .us, 0.1), "oz")
        try expectEqual(try autoConvertTargetLabel(.mass, .us, 5), "lb")
        try expectEqual(try autoConvertTargetLabel(.mass, .uk, 5), "kg")
        try expectEqual(try autoConvertTargetLabel(.volume, .metric, 0.0005), "ml")
        try expectEqual(try autoConvertTargetLabel(.volume, .metric, 0.005), "L")
        try expectEqual(try autoConvertTargetLabel(.volume, .us, 0.001), "fl oz")
        try expectEqual(try autoConvertTargetLabel(.volume, .us, 0.01), "gal")
        try expectEqual(try autoConvertTargetLabel(.volume, .uk, 0.001), "uk fl oz")
        try expectEqual(try autoConvertTargetLabel(.volume, .uk, 0.01), "uk gal")
        try expectEqual(try autoConvertTargetLabel(.area, .metric, 0.001), "cm²")
        try expectEqual(try autoConvertTargetLabel(.area, .metric, 1), "m²")
        try expectEqual(try autoConvertTargetLabel(.area, .metric, 1e7), "km²")
        try expectEqual(try autoConvertTargetLabel(.area, .us, 0.01), "in²")
        try expectEqual(try autoConvertTargetLabel(.area, .us, 1), "ft²")
        try expectEqual(try autoConvertTargetLabel(.area, .us, 1e7), "mi²")
        try expectEqual(try autoConvertTargetLabel(.area, .uk, 0.001), "cm²")
        try expectEqual(try autoConvertTargetLabel(.area, .uk, 1), "m²")
        try expectEqual(try autoConvertTargetLabel(.area, .uk, 1e7), "mi²")
        try expectEqual(try autoConvertTargetLabel(.speed, .metric, 1), "km/h")
        try expectEqual(try autoConvertTargetLabel(.speed, .us, 1), "mph")
        try expectEqual(try autoConvertTargetLabel(.speed, .uk, 1), "mph")
        try expectEqual(try autoConvertTargetLabel(.acceleration, .metric, 1), "m/s²")
        try expectEqual(try autoConvertTargetLabel(.acceleration, .us, 1), "ft/s²")
        try expectEqual(try autoConvertTargetLabel(.acceleration, .uk, 1), "m/s²")
        try expectEqual(try autoConvertTargetLabel(.temperature, .metric, 273.15), "C°")
        try expectEqual(try autoConvertTargetLabel(.temperature, .us, 273.15), "F°")
        try expectEqual(try autoConvertTargetLabel(.temperature, .uk, 273.15), "C°")
        try expectEqual(try autoConvertTargetLabel(.pressure, .metric, 1000), "kPa")
        try expectEqual(try autoConvertTargetLabel(.pressure, .us, 1000), "psi")
        try expectEqual(try autoConvertTargetLabel(.density, .metric, 1000), "kg/m³")
        try expectEqual(try autoConvertTargetLabel(.density, .us, 1000), "lb/ft³")
        try expectEqual(try autoConvertTargetLabel(.fuel, .metric, 1e-5), "L/100km")
        try expectEqual(try autoConvertTargetLabel(.fuel, .us, 1e-5), "US mpg")
        try expectEqual(try autoConvertTargetLabel(.fuel, .uk, 1e-5), "UK mpg")
        // The injectable locale mapping.
        try expectEqual(LocalUnitSystem.from(.us), .us)
        try expectEqual(LocalUnitSystem.from(.uk), .uk)
        try expectEqual(LocalUnitSystem.from(.metric), .metric)
        try expectEqual(LocalUnitSystem.resolve("nonsense"), .metric)
    },
    EngineCase("auto-convert-custom-unit-is-never-converted") {
        // A custom unit is not a built-in atom: it is never converted.
        let def = UserUnitDefinition(name: "zorch", definition: "660 feet")
        let resolution = UnitResolver.resolve([def])
        guard case .active = resolution.rows[0].status else {
            throw CaseFailure(message: "zorch is not active: \(resolution.rows[0].status)")
        }
        let result = autoConvertEval("5 zorch", .us, unitContext: resolution.context)
        guard case .number(_, let unit, _, _)? = result else {
            throw CaseFailure(message: "custom unit line must evaluate: \(String(describing: result))")
        }
        try expectEqual(unit, "zorch", "a custom unit keeps its own label")
    },
    EngineCase("auto-convert-preference-persistence") {
        // Additive, failure-proof, version 2, nothing in `.nlx`.
        let legacy = """
        {"sheets":[],"selectedIndex":0,
         "settings":{"decimalPlaces":7,"fontSizeKey":"ts","language":"en",
                     "sheetName":"S","lineNumbers":false,"fontColor":"white"},
         "version":2}
        """
        let payload = try JSONDecoder().decode(StorePayload.self, from: Data(legacy.utf8))
        try expectEqual(payload.settings.autoConvertUnits, .off)
        try expectEqual(payload.version, 2, "no store-version bump")
        let malformed = """
        {"sheets":[],"selectedIndex":0,
         "settings":{"decimalPlaces":7,"fontSizeKey":"ts","language":"en",
                     "sheetName":"S","lineNumbers":false,"fontColor":"white",
                     "autoConvertUnits":42},
         "version":2}
        """
        let bad = try JSONDecoder().decode(StorePayload.self, from: Data(malformed.utf8))
        try expectEqual(bad.settings.autoConvertUnits, .off, "malformed falls back to Off")
        var settings = AppSettings.defaults
        settings.autoConvertUnits = .localUnits
        let roundtrip = try JSONDecoder().decode(
            StorePayload.self,
            from: JSONEncoder().encode(StorePayload(sheets: [], selectedIndex: 0,
                                                    settings: settings, version: 2)))
        try expectEqual(roundtrip.settings.autoConvertUnits, .localUnits)
        try expectEqual(roundtrip.settings.localUnitSystem(measurementSystem: .us), .us)
        try expectEqual(roundtrip.settings.localUnitSystem(measurementSystem: .uk), .uk)
        try expectEqual(roundtrip.settings.localUnitSystem(measurementSystem: .metric), .metric)
        // `.nlx` never carries it, and an evaluation-context toggle never
        // rewrites the source text.
        let exported = try JSONEncoder().encode(SheetExport(title: "T", content: "3 km"))
        let object = try JSONSerialization.jsonObject(with: exported) as! [String: Any]
        try expect(object["autoConvertUnits"] == nil, "no auto-convert key in .nlx")
        var source = "3 km"
        _ = autoConvertEval(source, .us)
        try expectEqual(source, "3 km", "the source text is never rewritten")
        source = "3 km"
        try expectEqual(source, "3 km")
    },
    EngineCase("auto-convert-source-contracts") {
        guard let evaluator = autoConvertSource("Sources/NumlexCore/Engine/Evaluator.swift"),
              let core = autoConvertSource("Sources/NumlexCore/Units/LocalUnitConversion.swift"),
              let model = autoConvertSource("Sources/NumlexApp/AppModel.swift"),
              let content = autoConvertSource("Sources/NumlexApp/Views/ContentView.swift"),
              let settingsView = autoConvertSource("Sources/NumlexApp/Views/SettingsView.swift"),
              let builder = autoConvertSource("Sources/NumlexCore/Export/ExportSnapshotBuilder.swift")
        else {
            throw CaseFailure(message: "auto-convert sources missing")
        }
        // The conversion is applied to the mixed-unit result, i.e. after
        // ordinary typed evaluation and before any aggregate observes it.
        try expect(evaluator.contains("LocalUnitConversion.applied(to: q, line: line,"),
                   "the mixed-unit branch applies the auto-conversion")
        try expect(evaluator.contains("localUnits: localUnits"),
                   "the sheet loop threads the context line by line")
        try expect(core.contains("static func standaloneQuantity("),
                   "the strict stand-alone probe exists")
        try expect(!core.contains("NSRegularExpression"),
                   "no regex patch around evaluation")
        // The app derives ONE context and uses it for both editor passes
        // and the export snapshot.
        try expect(model.contains("settings.localUnitSystem(measurementSystem: Locale.current.measurementSystem)"),
                   "the app derives the system from the macOS locale")
        try expectEqual(content.components(separatedBy: "localUnits: model.localUnitContext").count - 1, 3,
                        "both editor passes and the export context share one value")
        try expect(builder.contains("localUnits: context.localUnits"),
                   "the export resolves with the frozen system")
        try expect(settingsView.contains("model.setAutoConvertUnits($0)"),
                   "the Numbers picker writes through the model setter")
        try expect(settingsView.contains("L10n.t(\"numbers.autoConvert\", language: language)"),
                   "the group is localized")
        // Localization completeness for the four new keys.
        for language in AppLanguage.allCases {
            guard let table = L10n.translations[language] else {
                throw CaseFailure(message: "missing table for \(language)")
            }
            for key in autoConvertKeys {
                guard let value = table[key], !value.isEmpty else {
                    throw CaseFailure(message: "\(language) is missing \(key)")
                }
            }
        }
        try expectEqual(L10n.t("numbers.autoConvert.off", language: .ru), "Выключено")
        try expectEqual(L10n.t("numbers.autoConvert.localUnits", language: .zh), "本地单位")
    }
]
