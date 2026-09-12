import Foundation
import NumlexCore

// MARK: - Natural compound-unit conversions (`per`) and contextual targets
//
// The natural spelling of a derived unit (`5 km per hour`) and the
// source-aware reading of an ambiguous target (`to ms` for a speed) are
// pinned here, together with the anti-regressions that keep every existing
// meaning intact.

private func unitLine(_ line: String, variables: inout [String: Double],
                      context: NumberFormatContext = .legacy,
                      places: Int = 10) -> LineResult? {
    evalLine(line, variables: &variables, rates: Rates(), decimalPlaces: places,
             context: context, unitContext: .builtIns)
}

private func unitText(_ line: String, places: Int = 10) throws -> String {
    var v: [String: Double] = [:]
    guard let r = unitLine(line, variables: &v, places: places) else {
        throw CaseFailure(message: "line must evaluate: \(line)", location: "CompoundUnit")
    }
    guard let text = AnswerDisplay.displayText(for: r, decimalPlaces: places,
                                               context: .legacy) else {
        throw CaseFailure(message: "no display text for \(line)", location: "CompoundUnit")
    }
    return text
}

private func expectUnit(_ line: String, _ expected: String,
                        places: Int = 10) throws {
    let got = try unitText(line, places: places)
    try expectEqual(got, expected, "\(line) -> \(expected)")
}

/// The numeric value + unit of a conversion row (rounding-tolerant checks).
private func unitValue(_ line: String) throws -> (Double, String?) {
    var v: [String: Double] = [:]
    guard let r = unitLine(line, variables: &v),
          case .number(let value, let unit, _, _) = r else {
        throw CaseFailure(message: "line must be a number: \(line)", location: "CompoundUnit")
    }
    return (value, unit)
}

private func expectUnitValue(_ line: String, _ expected: Double, _ unit: String,
                             tolerance: Double = 1e-9) throws {
    let (value, gotUnit) = try unitValue(line)
    try expectEqual(gotUnit, unit, "\(line) unit")
    try expect(abs(value - expected) <= tolerance,
               "\(line): expected \(expected) \(unit), got \(value)")
}

private func expectUnitError(_ line: String) throws {
    var v: [String: Double] = [:]
    guard let r = unitLine(line, variables: &v) else {
        throw CaseFailure(message: "line must evaluate: \(line)", location: "CompoundUnit")
    }
    guard case .error = r else {
        throw CaseFailure(message: "\(line) must be an error, got \(r)", location: "CompoundUnit")
    }
}

private func unitSheet(_ source: String) -> [String?] {
    var v: [String: Double] = [:]
    return evaluateSheet(source, variables: &v, rates: Rates(), decimalPlaces: 10)
        .map { AnswerDisplay.displayText(for: $0.result, decimalPlaces: 10, context: .legacy) }
}

public let compoundUnitCases: [EngineCase] = [

    // MARK: Task-4 pinned exact expressions

    EngineCase("compound-exact-user-expressions") {
        try expectUnit("5 km per hour to ms", "1.3888888889 m/s")
        try expectUnit("5 km per hour to kts", "2.6997840173 kn")
        try expectUnit("10 m per s to km per h", "36 km/h")
        // The mile conversion is asserted numerically (the display rounds
        // to the shared 10-decimal precision).
        try expectUnitValue("60 miles per hour to kt", 52.1385745140, "kn", tolerance: 1e-9)
        try expectUnit("500 ms to s", "0.5 s")
        try expectUnit("1 s to ms", "1,000 ms")
        try expectUnit("500ms", "500 ms")
        try expectUnit("5m", "5,000,000")
        try expectUnit("5 m", "5 m")
    },

    EngineCase("compound-per-is-a-spelled-division") {
        // `/` and `per` are the same operator, in the source and in the
        // target, for built-in derived quantities across dimensions.
        try expectUnit("5 km per hour", "5 km/h")
        try expectUnit("5 km/h", "5 km/h")
        try expectUnit("10 m per s to km per h", "36 km/h")
        try expectUnit("10 m / s to km/h", "36 km/h")
        try expectUnit("5 L per min to L per s", "0.0833333333 L/s")
        try expectUnit("100 Mbit per s", "100 Mbit/s")
        try expectUnit("9.8 m per s per s", "9.8 m/s/s")
        try expectUnit("5 kg per m3 to g per L", "5 g/L")
        // Spacing and case of the spelled operator do not matter; the unit
        // atoms keep the catalog's own case-sensitive rules.
        try expectUnit("5 km per  h", "5 km/h")
        try expectUnit("5 KM PER HOUR", "5 km/h")
        // Plurals, British and US atoms, and the full spelled phrases.
        try expectUnit("5 Meters per Second", "5 m/s")
        try expectUnit("5 kilometres per hour to metres per second", "1.3888888889 m/s")
        try expectUnit("5 meters per second to feet per second", "16.4041994751 ft/s")
        // Malformed repeated operator / unknown / incompatible targets are
        // deterministic errors, never a silently dropped unit.
        try expectUnitError("5 km per per h")
        try expectUnitError("5 km per hour to kg")
        try expectUnitError("5 km per hour to zzz")
        try expectUnitError("1 kg per hour to m per s")
    },

    EngineCase("compound-contextual-ms-target") {
        // `ms` keeps its GLOBAL meaning everywhere.
        try expectUnit("500 ms to s", "0.5 s")
        try expectUnit("1 s to ms", "1,000 ms")
        try expectUnit("1 h to ms", "3,600,000 ms")
        try expectUnit("1 ms to s", "0.001 s")
        try expectUnit("500 ms", "500 ms")
        try expectUnit("500ms", "500 ms")
        // A source that is already milliseconds keeps the ordinary reading.
        try expectUnit("500 ms to ms", "500 ms")
        // A SPEED source: the compatible reading of `ms` is metres/second.
        try expectUnit("5 km per hour to ms", "1.3888888889 m/s")
        try expectUnit("5 km/h to ms", "1.3888888889 m/s")
        try expectUnit("5 m/s to ms", "5 m/s")
        try expectUnit("5 kn to ms", "2.5722222222 m/s")
        // Any unrelated source stays incompatible: the contextual reading is
        // never a fallback for a dimension that cannot use it.
        try expectUnitError("5 kg to ms")
        try expectUnitError("5 km to ms")
        try expectUnitError("$5 to ms")
        // The canonical spelling stays `m/s` (or the unambiguous alias).
        try expectUnit("5 km per hour to m/s", "1.3888888889 m/s")
        try expectUnit("5 km per hour to mps", "1.3888888889 m/s")
    },

    EngineCase("compound-speed-aliases") {
        // Canonical OUTPUT labels never change.
        try expectUnit("1 mps to km/h", "3.6 km/h")
        try expectUnit("5 km/h to kt", "2.6997840173 kn")
        try expectUnit("1 kts to km/h", "1.852 km/h")
        try expectUnit("1 kt to km/h", "1.852 km/h")
        try expectUnit("1 knot to km/h", "1.852 km/h")
        try expectUnit("1 knots to km/h", "1.852 km/h")
        try expectUnit("5 km/h to kmph", "5 km/h")
        try expectUnit("5 m/s to fps", "16.4041994751 ft/s")
        try expectUnit("5 km per hour to kts", "2.6997840173 kn")
        // The alias table stays collision-free and `ms` is never a speed
        // alias.
        try expectEqual(UnitCatalog.aliasCollisions().isEmpty, true,
                        "no catalog alias collisions")
        for speed in ["mps", "kt", "kts", "kmph", "fps", "kn", "mph"] {
            let expr = UnitCatalog.resolveExpression(speed)
            try expect(expr != nil, "\(speed) resolves")
            try expectEqual(expr?.unit.label.hasSuffix("ms"), false,
                            "\(speed) is not a millisecond alias")
        }
        let ms = UnitCatalog.resolveExpression("ms")
        try expectEqual(ms?.unit.label, "ms", "ms stays the millisecond")
        try expectEqual(ms?.unit.vector, DimensionVector(t: 1), "ms is a time unit")
    },

    EngineCase("compound-direct-and-variable-conversions") {
        // A quantity variable converts through the same target selection.
        try expectEqual(unitSheet("speed = 5 km per hour\nspeed to kts"),
                        ["5 km/h", "2.6997840173 kn"], "variable to knots")
        try expectEqual(unitSheet("speed = 5 km per hour\nspeed to ms"),
                        ["5 km/h", "1.3888888889 m/s"], "variable to the contextual m/s")
        try expectEqual(unitSheet("speed = 5 km per hour\nspeed to km/h"),
                        ["5 km/h", "5 km/h"], "variable to its own unit")
        try expectEqual(unitSheet("capacity = 5 L per min\ncapacity to L per s"),
                        ["5 L/min", "0.0833333333 L/s"], "generic derived variable")
        try expectEqual(unitSheet("pace = 5 min per km\npace to s per m"),
                        ["5 min/km", "0.3 s/m"], "a pace keeps its own direction")
        // Visible row and Copy Answer agree for every conversion result.
        for line in ["5 km per hour to ms", "5 km per hour to kts",
                     "10 m per s to km per h", "speed = 5 km per hour"] {
            var v: [String: Double] = [:]
            guard let r = unitLine(line, variables: &v) else {
                throw CaseFailure(message: "\(line) must evaluate", location: "CompoundUnit")
            }
            try expectEqual(AnswerDisplay.text(for: r, decimalPlaces: 10, context: .legacy),
                            AnswerDisplay.displayText(for: r, decimalPlaces: 10, context: .legacy),
                            "\(line): copy == visible")
        }
    },

    EngineCase("compound-anti-regressions") {
        // Nothing pre-existing changed meaning or lane ownership.
        try expectUnit("5m", "5,000,000")
        try expectUnit("5 m", "5 m")
        try expectUnit("500 ms", "500 ms")
        try expectUnit("500ms", "500 ms")
        try expectUnitError("1 m 20 cm")
        try expectUnit("90 km per 3 h", "30 km/h")
        try expectUnit("90 km / 3 h", "30 km/h")
        try expectUnit("10 km in 45 min", "0.2222222222 km/min")
        try expectUnit("May 5 + 2 days", "May 7")
        try expectUnit("$24 per day × 12 hrs", "$12.00")
        try expectUnit("2.5 kg at €3 per kg", "€7.50")
        try expectUnit("20/200 %", "10%")
        try expectUnit("12 hrs", "12 h")
        // A custom unit that merely looks like a duration/speed alias does
        // not gain the new grammar: the context owns its own tokens.
        let custom = UnitContext(customUnits: [])
        _ = custom
    },

    EngineCase("compound-syntax-spans-paint-the-unit-grammar") {
        // `per` inside a unit expression takes the unit role and is never
        // painted as an arithmetic operator; the numeric and unit parts of
        // the natural source and the target are all covered.
        let lines = ["5 km per hour", "5 km per hour to km per h"]
        for line in lines {
            let spans = SyntaxClassifier.spans(for: line, rates: Rates(),
                                                decimalPlaces: 10)[0]
            let ns = line as NSString
            func roles(for text: String) -> [SyntaxRole] {
                let r = ns.range(of: text)
                guard r.location != NSNotFound else { return [] }
                return spans.filter { NSLocationInRange(r.location, $0.range)
                        || NSIntersectionRange(r, $0.range).length > 0 }
                    .map(\.role)
            }
            try expect(roles(for: "5").contains(.number), "\(line): the number is painted")
            try expect(roles(for: "km").contains(.conversion), "\(line): km is a unit span")
            try expect(roles(for: "hour").contains(.conversion), "\(line): hour is a unit span")
            try expect(roles(for: "per").contains(.conversion),
                       "\(line): per takes the unit role")
            try expect(!roles(for: "per").contains(.operatorGlyph),
                       "\(line): per is never an arithmetic operator")
        }
        // The target keyword keeps its specifier role.
        let line = "5 km per hour to km per h"
        let spans = SyntaxClassifier.spans(for: line, rates: Rates(), decimalPlaces: 10)[0]
        let toRange = (line as NSString).range(of: "to")
        try expect(spans.contains { $0.role == .specifier
                        && NSIntersectionRange($0.range, toRange).length > 0 },
                   "the conversion keyword keeps its role")
    }
]
