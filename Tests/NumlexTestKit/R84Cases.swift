//
//  R84Cases.swift
//  NumlexTestKit
//
//  R84: unit arithmetic, custom units, pixels/PPI, cooking densities
//  and generalized rates. These cases pin the R84 contract on top of
//  the legacy suite: real quantity algebra (value + dimension vector
//  + family), strict line ownership (shape-owned lines never degrade
//  to word stripping), and the shared UnitContext threading.
//

import NumlexCore
import Foundation

/// The R84 case collection (all tasks).
public var r84Cases: [EngineCase] {
    r84MixedUnitCases + r84CustomUnitCases + r84PpiCases + r84DensityCases + r84RateCases + r84UnitUiCases + r84TokenFormattingCases + r84SyntaxCases
}

// MARK: - helpers

/// Evaluates a whole sheet (shared environment) and returns the
/// per-line results in source order. `now`/`calendar` default to the
/// shared fixed reference so date-adjacent lines stay deterministic.
@discardableResult
func r84Sheet(_ source: String,
              rates: Rates = Rates(),
              context: NumberFormatContext = .legacy,
              unitContext: UnitContext = .builtIns,
              now: Date = r84Now,
              calendar: Calendar = r84Calendar) -> [SheetLine] {
    var vars: [String: Double] = [:]
    return evaluateSheet(source, variables: &vars, rates: rates,
                         decimalPlaces: 6, now: now, calendar: calendar,
                         context: context, unitContext: unitContext)
}

/// The fixed reference clock for R84 tests (mid-winter 2026).
let r84Calendar: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "America/New_York")!
    return cal
}()
let r84Now: Date = r84Calendar.date(
    from: DateComponents(year: 2026, month: 1, day: 15, hour: 12))!

/// The `.number` value of a line result (test-local unwrapping).
func r84Value(_ line: SheetLine) -> Double? {
    guard case .number(let v, _, _, _) = line.result else { return nil }
    return v
}

/// The `.number` unit label of a line result (nil for unitless).
func r84Unit(_ line: SheetLine) -> String? {
    guard case .number(_, let u, _, _) = line.result, let u = u, !u.isEmpty else { return nil }
    return u
}

func r84IsError(_ line: SheetLine) -> Bool {
    if case .error = line.result { return true }
    return false
}

/// Close within a relative tolerance (unit values are computed
/// through base factors — 1e-9 relative is far below display).
func r84Close(_ a: Double?, _ b: Double, _ label: String) throws {
    guard let a = a, abs(a - b) <= max(1e-9, 1e-9 * abs(b)) else {
        throw CaseFailure(message: "r84 \(label): expected ~\(b), got \(String(describing: a))")
    }
}

// MARK: - Task 2: mixed unit expression engine

public let r84MixedUnitCases: [EngineCase] = [
    EngineCase("r84-mixed-addition") {
        let r = r84Sheet("""
        1 km + 1000 m
        1000 m + 1 km
        2 km - 500 m
        10 m × 10 m
        10 m + 5
        300 + 20 km
        20 km + 300
        """)
        try r84Close(r84Value(r[0]), 2, "1 km + 1000 m")
        guard r84Unit(r[0]) == "km" else { throw CaseFailure(message: "1 km + 1000 m unit = \(String(describing: r84Unit(r[0])))") }
        try r84Close(r84Value(r[1]), 2, "1000 m + 1 km")
        guard r84Unit(r[1]) == "km" else { throw CaseFailure(message: "order: unit = \(String(describing: r84Unit(r[1])))") }
        try r84Close(r84Value(r[2]), 1.5, "2 km - 500 m")
        guard r84Unit(r[2]) == "km" else { throw CaseFailure(message: "sub: \(String(describing: r84Unit(r[2])))") }
        try r84Close(r84Value(r[3]), 100, "10 m × 10 m")
        guard r84Unit(r[3]) == "m²" else { throw CaseFailure(message: "area: \(String(describing: r84Unit(r[3])))") }
        try r84Close(r84Value(r[4]), 15, "10 m + 5")
        guard r84Unit(r[4]) == "m" else { throw CaseFailure(message: "plain assimilation: \(String(describing: r84Unit(r[4])))") }
        // Plain-side assimilation counts in the quantity's DISPLAY unit.
        try r84Close(r84Value(r[5]), 320, "300 + 20 km")
        guard r84Unit(r[5]) == "km" else { throw CaseFailure(message: "300 + 20 km: \(String(describing: r84Unit(r[5])))") }
        try r84Close(r84Value(r[6]), 320, "20 km + 300")
        guard r84Unit(r[6]) == "km" else { throw CaseFailure(message: "20 km + 300: \(String(describing: r84Unit(r[6])))") }
    },

    EngineCase("r84-mixed-rates") {
        let r = r84Sheet("""
        90 km / 3 day
        3 hours / 3 days
        3 hours / day
        10 km / day
        7 day / 2
        2.5 kg / 5 L
        """)
        try r84Close(r84Value(r[0]), 30, "90 km / 3 day")
        guard r84Unit(r[0]) == "km/day" else { throw CaseFailure(message: "rate label: \(String(describing: r84Unit(r[0])))") }
        try r84Close(r84Value(r[1]), 1.0 / 24.0, "3 hours / 3 days")
        // Same-signature cancellation is a plain scalar (no unit).
        guard r84Unit(r[1]) == nil else { throw CaseFailure(message: "cancellation keeps a unit: \(String(describing: r84Unit(r[1])))") }
        try r84Close(r84Value(r[2]), 3, "3 hours / day")
        guard r84Unit(r[2]) == "h/day" else { throw CaseFailure(message: "bare-unit rate: \(String(describing: r84Unit(r[2])))") }
        try r84Close(r84Value(r[3]), 10, "10 km / day")
        guard r84Unit(r[3]) == "km/day" else { throw CaseFailure(message: "km/day: \(String(describing: r84Unit(r[3])))") }
        try r84Close(r84Value(r[4]), 3.5, "7 day / 2")
        guard r84Unit(r[4]) == "day" else { throw CaseFailure(message: "plain divisor: \(String(describing: r84Unit(r[4])))") }
        try r84Close(r84Value(r[5]), 0.5, "2.5 kg / 5 L")
        guard r84Unit(r[5]) == "kg/L" else { throw CaseFailure(message: "kg/L: \(String(describing: r84Unit(r[5])))") }
    },

    EngineCase("r84-mixed-targets") {
        let r = r84Sheet("""
        10 km in m
        10 m in km
        5 miles in km
        1 ft in m
        300 km / 2.5 hours in mph
        5 km / h to m / s
        """)
        try r84Close(r84Value(r[0]), 10000, "10 km in m")
        guard r84Unit(r[0]) == "m" else { throw CaseFailure(message: "target m: \(String(describing: r84Unit(r[0])))") }
        try r84Close(r84Value(r[1]), 0.01, "10 m in km")
        guard r84Unit(r[1]) == "km" else { throw CaseFailure(message: "target km: \(String(describing: r84Unit(r[1])))") }
        try r84Close(r84Value(r[2]), 8.04672, "5 miles in km")
        try r84Close(r84Value(r[3]), 0.3048, "1 ft in m")
        try r84Close(r84Value(r[4]), 300.0 / 2.5 / 1.609344, "300 km / 2.5 hours in mph")
        guard r84Unit(r[4]) == "mph" else { throw CaseFailure(message: "mph target: \(String(describing: r84Unit(r[4])))") }
        try r84Close(r84Value(r[5]), 5.0 / 3.6, "5 km/h to m/s")
        guard r84Unit(r[5]) == "m/s" else { throw CaseFailure(message: "m/s target: \(String(describing: r84Unit(r[5])))") }
    },

    EngineCase("r84-mixed-strictness") {
        // Family walls: the unit family of an operand is never
        // coerced — a currency quantity or a temperature is rejected
        // in the algebra (the money/temperature lanes own those lines).
        let r = r84Sheet("""
        1 kg + 1 m
        10 $ + 5 m
        """)
        guard r84IsError(r[0]) else { throw CaseFailure(message: "mass + length must error") }
        guard r84IsError(r[1]) else { throw CaseFailure(message: "money must not enter the unit algebra") }
        // A shape-owned line that cannot parse is a visible error —
        // it NEVER degrades to word stripping.
        let e = r84Sheet("10 km +")
        guard r84IsError(e[0]) else { throw CaseFailure(message: "dangling operator must error") }
    },

    EngineCase("r84-mixed-ownership") {
        // Conversion-shaped lines stay in the conversion lane (full
        // unit expressions: compound from/to, qualifiers, fuel).
        let r = r84Sheet("""
        10 km to m
        1 bbl/d to L/s
        1 km/L to L/100km
        10 km/L to US mpg
        1 kgf/cm2 to kPa
        1 hp (electric) to W
        """)
        try r84Close(r84Value(r[0]), 10000, "10 km to m")
        guard r84Unit(r[0]) == "m" else { throw CaseFailure(message: "10 km to m: \(String(describing: r84Unit(r[0])))") }
        guard !r84IsError(r[1]) else {
            throw CaseFailure(message: "bbl/d: \(String(describing: r[1].result))")
        }
        try r84Close(r84Value(r[1]), 0.0018401307, "1 bbl/d to L/s")
        try r84Close(r84Value(r[2]), 100, "1 km/L to L/100km")
        guard r84Unit(r[2]) == "L/100km" else { throw CaseFailure(message: "L/100km: \(String(describing: r84Unit(r[2])))") }
        try r84Close(r84Value(r[3]), 23.5214583333, "10 km/L to US mpg")
        try r84Close(r84Value(r[4]), 98.0665, "1 kgf/cm2 to kPa")
        guard r84Unit(r[4]) == "kPa" else { throw CaseFailure(message: "kPa: \(String(describing: r84Unit(r[4])))") }
        try r84Close(r84Value(r[5]), 746, "1 hp (electric) to W")
    },

    EngineCase("r84-mixed-assignment") {
        let r = r84Sheet("""
        x = 1 km + 2 km
        x + 500 m
        speed = 90 km / 3 day
        speed × 2 day
        """)
        try r84Close(r84Value(r[0]), 3, "x = 1 km + 2 km")
        guard r84Unit(r[0]) == "km" else { throw CaseFailure(message: "x unit: \(String(describing: r84Unit(r[0])))") }
        // The quantity name participates in later unit lines.
        try r84Close(r84Value(r[1]), 3.5, "x + 500 m")
        guard r84Unit(r[1]) == "km" else { throw CaseFailure(message: "x + 500 m: \(String(describing: r84Unit(r[1])))") }
        try r84Close(r84Value(r[2]), 30, "speed = 90 km / 3 day")
        guard r84Unit(r[2]) == "km/day" else { throw CaseFailure(message: "speed: \(String(describing: r84Unit(r[2])))") }
        try r84Close(r84Value(r[3]), 60, "speed × 2 day")
        guard r84Unit(r[3]) == "km" else { throw CaseFailure(message: "speed × 2 day: \(String(describing: r84Unit(r[3])))") }
    },

    EngineCase("r84-mixed-percent-scaling") {
        let r = r84Sheet("""
        20% of 100 km
        15% of 200 m
        50% of 10 L
        """)
        try r84Close(r84Value(r[0]), 20, "20% of 100 km")
        guard r84Unit(r[0]) == "km" else { throw CaseFailure(message: "% of km: \(String(describing: r84Unit(r[0])))") }
        try r84Close(r84Value(r[1]), 30, "15% of 200 m")
        guard r84Unit(r[1]) == "m" else { throw CaseFailure(message: "% of m: \(String(describing: r84Unit(r[1])))") }
        try r84Close(r84Value(r[2]), 5, "50% of 10 L")
        guard r84Unit(r[2]) == "L" else { throw CaseFailure(message: "% of L: \(String(describing: r84Unit(r[2])))") }
    },

    EngineCase("r84-mixed-legacy-coexistence") {
        // The pre-R84 lanes keep their exact behavior around the new
        // stage: compact suffixes, date lines, percentages, prose.
        let r = r84Sheet("""
        2 M
        5 m
        May 5 + 43 days
        100 + 10%
        20/200 %
        """)
        try r84Close(r84Value(r[0]), 2_000_000, "2 M compact")
        guard r84Unit(r[0]) == nil else { throw CaseFailure(message: "compact keeps no unit: \(String(describing: r84Unit(r[0])))") }
        try r84Close(r84Value(r[1]), 5, "5 m")
        guard r84Unit(r[1]) == "m" else { throw CaseFailure(message: "5 m: \(String(describing: r84Unit(r[1])))") }
        guard case .date(let y, let mo, let d, _) = r[2].result else {
            throw CaseFailure(message: "date line stolen: \(String(describing: r[2].result))")
        }
        guard y == 2026, mo == 6, d == 17 else {
            throw CaseFailure(message: "May 5 + 43 days = \(y)-\(mo)-\(d)")
        }
        try r84Close(r84Value(r[3]), 110, "100 + 10%")
        try r84Close(r84Value(r[4]), 0.1, "20/200 %")
        guard case .number(_, _, .percent, _) = r[4].result else {
            throw CaseFailure(message: "terminal % kind: \(String(describing: r[4].result))")
        }
    }
]

// MARK: - placeholders for the remaining R84 tasks (filled in as each
// task lands; the aggregate above references them from day one).

public // MARK: Custom units (resolver + context)

let r84CustomUnitCases: [EngineCase] = [
    EngineCase("r84-custom-active") {
        let rows = [
            UserUnitDefinition(name: "zorch", definition: "660 feet")
        ]
        let res = UnitResolver.resolve(rows)
        guard case .active = res.rows[0].status else {
            throw CaseFailure(message: "zorch: \(res.rows[0].status)")
        }
        let lines = r84Sheet("10 zorch to m\n5 zorchs to km", unitContext: res.context)
        try r84Close(r84Value(lines[0]), 2011.68, "10 zorch to m")
        try r84Close(r84Value(lines[1]), 1.00584, "5 zorchs to km")
    },
    EngineCase("r84-custom-alias-plural") {
        let rows = [UserUnitDefinition(name: "gudgeon", definition: "0.5 m")]
        let res = UnitResolver.resolve(rows)
        let lines = r84Sheet("2 gudgeons + 1 m", unitContext: res.context)
        try r84Close(r84Value(lines[0]), 2, "2 gudgeons + 1 m")
        guard r84Unit(lines[0]) == "m" else {
            throw CaseFailure(message: "gudgeon plural: \(String(describing: r84Unit(lines[0])))")
        }
    },
    EngineCase("r84-custom-dependency-chain") {
        // g2 depends on g1 which is defined below it: the fixed point
        // resolves both.
        let rows = [
            UserUnitDefinition(name: "bigg", definition: "3 smigg"),
            UserUnitDefinition(name: "smigg", definition: "2 m")
        ]
        let res = UnitResolver.resolve(rows)
        guard case .active = res.rows[0].status, case .active = res.rows[1].status
        else { throw CaseFailure(message: "chain: \(res.rows.map(\.status))") }
        let lines = r84Sheet("1 bigg to m", unitContext: res.context)
        try r84Close(r84Value(lines[0]), 6, "1 bigg to m")
    },
    EngineCase("r84-custom-new-dimension") {
        let rows = [
            UserUnitDefinition(name: "flurb", definition: "new unit"),
            UserUnitDefinition(name: "meble", definition: "4 flurb")
        ]
        let res = UnitResolver.resolve(rows)
        guard case .active = res.rows[0].status, case .active = res.rows[1].status
        else { throw CaseFailure(message: "newdim: \(res.rows.map(\.status))") }
        let lines = r84Sheet("2 flurb + 3 flurb\n5 flurb to meble\n2 flurb + 1 m",
                            unitContext: res.context)
        try r84Close(r84Value(lines[0]), 5, "2 flurb + 3 flurb")
        guard r84Unit(lines[0]) == "flurb" else {
            throw CaseFailure(message: "newdim unit: \(String(describing: r84Unit(lines[0])))")
        }
        try r84Close(r84Value(lines[1]), 1.25, "5 flurb to meble")
        guard r84IsError(lines[2]) else {
            throw CaseFailure(message: "newdim + m must error")
        }
    },
    EngineCase("r84-custom-statuses") {
        let res = UnitResolver.resolve([
            UserUnitDefinition(name: "", definition: ""),           // empty
            UserUnitDefinition(name: "half", definition: ""),      // incomplete
            UserUnitDefinition(name: "7th", definition: "1 m"),    // invalidName
            UserUnitDefinition(name: "twin", definition: "1 m"),
            UserUnitDefinition(name: "twin", definition: "2 m"),   // duplicate
            UserUnitDefinition(name: "mile", definition: "8 fc"),  // builtIn
            UserUnitDefinition(name: "qwib", definition: "123"),   // invalidDefinition
            UserUnitDefinition(name: "loop", definition: "1 loop") // cycle
        ], constants: [UserConstant(name: "speed", expression: "5")])
        let got = res.rows.map { $0.status }
        let want: [CustomUnitStatus] = [
            .empty, .incomplete, .invalidName, .duplicate, .duplicate,
            .builtInCollision, .invalidDefinition, .cycle
        ]
        guard got == want else { throw CaseFailure(message: "statuses: \(got)") }
    },
    EngineCase("r84-custom-constant-collision") {
        let res = UnitResolver.resolve(
            [UserUnitDefinition(name: "speed", definition: "1 m")],
            constants: [UserConstant(name: "speed", expression: "5")])
        guard case .constantCollision = res.rows[0].status else {
            throw CaseFailure(message: "const collision: \(res.rows[0].status)")
        }
    },
    EngineCase("r84-custom-unknown-dep") {
        let res = UnitResolver.resolve([
            UserUnitDefinition(name: "solo", definition: "2 ghostly")
        ])
        guard case .unknownDependency = res.rows[0].status else {
            throw CaseFailure(message: "unknown: \(res.rows[0].status)")
        }
        // The inactive row is absent from the context: built-ins still work.
        let lines = r84Sheet("1 m to km", unitContext: res.context)
        try r84Close(r84Value(lines[0]), 0.001, "1 m to km")
    },
    EngineCase("r84-custom-limit") {
        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        let rows = (0..<102).map { i in
            let name = "q" + String(letters[i / 26]) + String(letters[i % 26])
            return UserUnitDefinition(name: name, definition: "\(i + 1) m")
        }
        let res = UnitResolver.resolve(rows)
        let active = res.rows.filter { $0.status == .active }.count
        guard active == 99 else {
            throw CaseFailure(message: "limit: \(active) active")
        }
        guard case .exceedsLimit = res.rows[100].status else {
            throw CaseFailure(message: "overflow: \(res.rows[100].status)")
        }
    },
    EngineCase("r84-custom-builtin-untouched") {
        // An inactive collision never breaks the built-in it would shadow.
        let res = UnitResolver.resolve([
            UserUnitDefinition(name: "mile", definition: "1 furlong")
        ])
        let lines = r84Sheet("1 mile to km", unitContext: res.context)
        try r84Close(r84Value(lines[0]), 1.609344, "1 mile to km (built-in intact)")
    },
]
public let r84PpiCases: [EngineCase] = [
    EngineCase("r84-ppi-length-to-pixels") {
        let lines = r84Sheet("1 cm in px at 326 ppi\n10 cm as px at 96 ppi\n1 in in px at 96 ppi")
        try r84Close(r84Value(lines[0]), 0.01 * 326 / 0.0254, "1 cm in px at 326 ppi")
        guard r84Unit(lines[0]) == "px" else {
            throw CaseFailure(message: "px unit: \(String(describing: r84Unit(lines[0])))")
        }
        try r84Close(r84Value(lines[1]), 0.1 * 96 / 0.0254, "10 cm as px at 96 ppi")
        try r84Close(r84Value(lines[2]), 96, "1 in in px at 96 ppi")
    },
    EngineCase("r84-ppi-pixels-to-length") {
        let lines = r84Sheet("100 px at 326 ppi in cm\n96 px at 96 ppi in in\n640 px at 100 ppi in m")
        try r84Close(r84Value(lines[0]), 100 * 0.0254 / 326 * 100, "100 px at 326 ppi in cm")
        guard r84Unit(lines[0]) == "cm" else {
            throw CaseFailure(message: "cm unit: \(String(describing: r84Unit(lines[0])))")
        }
        try r84Close(r84Value(lines[1]), 1, "96 px at 96 ppi in in")
        try r84Close(r84Value(lines[2]), 640 * 0.0254 / 100, "640 px at 100 ppi in m")
    },
    EngineCase("r84-ppi-strictness") {
        let lines = r84Sheet("1 cm in px at 0 ppi\n1 kg in px at 96 ppi\n10 px at 96 ppi in kg")
        guard r84IsError(lines[0]) else {
            throw CaseFailure(message: "zero ppi must error: \(String(describing: lines[0].result))")
        }
        guard r84IsError(lines[1]) else {
            throw CaseFailure(message: "kg source must error: \(String(describing: lines[1].result))")
        }
        guard r84IsError(lines[2]) else {
            throw CaseFailure(message: "kg target must error: \(String(describing: lines[2].result))")
        }
    },
    EngineCase("r84-px-not-a-length") {
        let lines = r84Sheet("10 px\n10 px + 5 px\n10 px + 1 m\n10 px / 2\n10 px × 3")
        try r84Close(r84Value(lines[0]), 10, "10 px")
        guard r84Unit(lines[0]) == "px" else {
            throw CaseFailure(message: "px label: \(String(describing: r84Unit(lines[0])))")
        }
        try r84Close(r84Value(lines[1]), 15, "10 px + 5 px")
        guard r84Unit(lines[1]) == "px" else {
            throw CaseFailure(message: "px+px label: \(String(describing: r84Unit(lines[1])))")
        }
        guard r84IsError(lines[2]) else {
            throw CaseFailure(message: "px + m must error: \(String(describing: lines[2].result))")
        }
        try r84Close(r84Value(lines[3]), 5, "10 px / 2")
        try r84Close(r84Value(lines[4]), 30, "10 px × 3")
    },
    EngineCase("r84-ppi-custom-length") {
        let rows = [UserUnitDefinition(name: "zorch", definition: "1 ft")]
        let res = UnitResolver.resolve(rows)
        let lines = r84Sheet("1 zorch in px at 96 ppi", unitContext: res.context)
        try r84Close(r84Value(lines[0]), 0.3048 * 96 / 0.0254, "1 zorch in px at 96 ppi")
    },
    EngineCase("r84-ppi-not-stolen") {
        // Near-miss shapes are NOT PPI phrases: `1 cm in px` is a
        // (failing) unit conversion, `1 cm at 326 ppi` is plain error
        // prose — neither is silently re-interpreted.
        let lines = r84Sheet("1 cm in px\n1 cm at 326 ppi")
        guard r84IsError(lines[0]) else {
            throw CaseFailure(message: "cm in px must error: \(String(describing: lines[0].result))")
        }
        guard r84IsError(lines[1]) else {
            throw CaseFailure(message: "cm at ppi must error: \(String(describing: lines[1].result))")
        }
    },
]
public let r84DensityCases: [EngineCase] = [
    EngineCase("r84-density-mass-to-volume") {
        // 200 g of flour: 0.2 kg / 528.3 kg/m³ = 3.7858e-4 m³ = 378.58 ml
        let lines = r84Sheet("200 g of flour to ml\n1 kg of sugar to L\n250 g of butter to tbsp")
        try r84Close(r84Value(lines[0]), 0.2 / 528.3 * 1e6, "200 g of flour to ml")
        guard r84Unit(lines[0]) == "ml" else {
            throw CaseFailure(message: "ml unit: \(String(describing: r84Unit(lines[0])))")
        }
        try r84Close(r84Value(lines[1]), 1.0 / 845.4 * 1000, "1 kg of sugar to L")
        try r84Close(r84Value(lines[2]), 0.25 / 959.4 / 1.478676478125e-5, "250 g of butter to tbsp")
    },
    EngineCase("r84-density-volume-to-mass") {
        let lines = r84Sheet("1 cup of flour to g\n1 cup of honey to g\n1 L of honey to kg\n2 tbsp of oil to ml")
        // 1 cup = 2.365882365e-4 m³; × 528.3 = 0.12499 kg ≈ 125 g
        try r84Close(r84Value(lines[0]), 0.0002365882365 * 528.3 * 1000, "1 cup of flour to g")
        guard r84Unit(lines[0]) == "g" else {
            throw CaseFailure(message: "g unit: \(String(describing: r84Unit(lines[0])))")
        }
        try r84Close(r84Value(lines[1]), 0.0002365882365 * 1437.1 * 1000, "1 cup of honey to g")
        try r84Close(r84Value(lines[2]), 0.001 * 1437.1, "1 L of honey to kg")
        try r84Close(r84Value(lines[3]), 2 * 1.478676478125e-5 * 1e6, "2 tbsp of oil to ml (same-kind)")
    },
    EngineCase("r84-density-multiword") {
        let lines = r84Sheet("1 cup of brown sugar to g\n200 g of icing sugar to ml")
        try r84Close(r84Value(lines[0]), 0.0002365882365 * 930.3 * 1000, "1 cup of brown sugar to g")
        try r84Close(r84Value(lines[1]), 0.2 / 507.2 * 1e6, "200 g of icing sugar to ml")
    },
    EngineCase("r84-density-strictness") {
        let lines = r84Sheet("200 g of kibble to ml\n200 g of flour to kg\n1 cup of flour to cup\n5 m of flour to ml")
        guard r84IsError(lines[0]) else {
            throw CaseFailure(message: "unknown ingredient: \(String(describing: lines[0].result))")
        }
        // Same-kind targets are plain unit conversions (density is
        // irrelevant): `200 g of flour to kg` = 0.2 kg, `1 cup of
        // flour to cup` = 1 cup.
        try r84Close(r84Value(lines[1]), 0.2, "200 g of flour to kg")
        guard r84Unit(lines[1]) == "kg" else {
            throw CaseFailure(message: "kg unit: \(String(describing: r84Unit(lines[1])))")
        }
        try r84Close(r84Value(lines[2]), 1, "1 cup of flour to cup")
        guard r84IsError(lines[3]) else {
            throw CaseFailure(message: "length operand: \(String(describing: lines[3].result))")
        }
    },
    EngineCase("r84-density-not-stolen") {
        // `50% of 200` stays percentage; `200 g of 2` is MIXED algebra
        // (`of` = multiply — the density shape needs a WORD ingredient
        // and a target unit, so it never fires on numbers).
        let lines = r84Sheet("50% of 200\n200 g of 2")
        try r84Close(r84Value(lines[0]), 100, "50% of 200")
        try r84Close(r84Value(lines[1]), 400, "200 g of 2 (mixed of = x)")
        guard r84Unit(lines[1]) == "g" else {
            throw CaseFailure(message: "g unit: \(String(describing: r84Unit(lines[1])))")
        }
    },
    EngineCase("r84-density-units-catalog") {
        // The density units themselves convert linearly.
        let lines = r84Sheet("1 g/cm³ to kg/m³\n1000 kg/m³ to g/L")
        try r84Close(r84Value(lines[0]), 1000, "1 g/cm³ to kg/m³")
        try r84Close(r84Value(lines[1]), 1000, "1000 kg/m³ to g/L")
    },
]
public let r84RateCases: [EngineCase] = [
    EngineCase("r84-rate-per-operator") {
        let lines = r84Sheet("90 km per 3 day\n45 min per 10 km\n100 miles per year")
        try r84Close(r84Value(lines[0]), 30, "90 km per 3 day")
        guard r84Unit(lines[0]) == "km/day" else {
            throw CaseFailure(message: "km/day: \(String(describing: r84Unit(lines[0])))")
        }
        try r84Close(r84Value(lines[1]), 4.5, "45 min per 10 km")
        guard r84Unit(lines[1]) == "min/km" else {
            throw CaseFailure(message: "min/km: \(String(describing: r84Unit(lines[1])))")
        }
        try r84Close(r84Value(lines[2]), 100, "100 miles per year")
        guard r84Unit(lines[2]) == "mi/yr" else {
            throw CaseFailure(message: "mi/yr: \(String(describing: r84Unit(lines[2])))")
        }
    },
    EngineCase("r84-rate-in-phrase") {
        let lines = r84Sheet("10 km in 45 min\n45 min in 10 km\n1 Gbit in 5 s")
        try r84Close(r84Value(lines[0]), 10.0 / 45.0, "10 km in 45 min")
        guard r84Unit(lines[0]) == "km/min" else {
            throw CaseFailure(message: "km/min: \(String(describing: r84Unit(lines[0])))")
        }
        try r84Close(r84Value(lines[1]), 4.5, "45 min in 10 km (pace)")
        guard r84Unit(lines[1]) == "min/km" else {
            throw CaseFailure(message: "pace: \(String(describing: r84Unit(lines[1])))")
        }
        try r84Close(r84Value(lines[2]), 0.2, "1 Gbit in 5 s (transfer)")
        guard r84Unit(lines[2]) == "Gbit/s" else {
            throw CaseFailure(message: "Gbit/s: \(String(describing: r84Unit(lines[2])))")
        }
    },
    EngineCase("r84-rate-calendar-year") {
        // The Gregorian average year is 365.2425 days: the same rate
        // expressed per day differs by that factor.
        let lines = r84Sheet("100 mi per year to mi/day\n100 mi in 1 year")
        let yr = 365.2425 * 86400.0
        let day = 86400.0
        _ = yr
        _ = day
        try r84Close(r84Value(lines[0]), 100 / 365.2425, "100 mi per year to mi/day")
        guard r84Unit(lines[0]) == "mi/day" else {
            throw CaseFailure(message: "mi/day: \(String(describing: r84Unit(lines[0])))")
        }
        try r84Close(r84Value(lines[1]), 100, "100 mi in 1 year")
    },
    EngineCase("r84-price-per-unit") {
        let lines = r84Sheet("2.5 kg at €3 per kg\n200 g at $7.50 per kg\n1 L at €2 per L")
        guard case .money(let v1, let c1) = lines[0].result else {
            throw CaseFailure(message: "€ price: \(String(describing: lines[0].result))")
        }
        try r84Close(v1, 7.5, "2.5 kg at €3 per kg")
        guard c1 == "EUR" else { throw CaseFailure(message: "code: \(c1)") }
        guard case .money(let v2, let c2) = lines[1].result else {
            throw CaseFailure(message: "$ price: \(String(describing: lines[1].result))")
        }
        try r84Close(v2, 1.5, "200 g at $7.50 per kg")
        guard c2 == "USD" else { throw CaseFailure(message: "code: \(c2)") }
        guard case .money(let v3, _) = lines[2].result else {
            throw CaseFailure(message: "€ L price: \(String(describing: lines[2].result))")
        }
        try r84Close(v3, 2.0, "1 L at €2 per L")
    },
    EngineCase("r84-price-strictness") {
        let lines = r84Sheet("2.5 kg at €3 per day\n2.5 at €3 per kg")
        guard r84IsError(lines[0]) else {
            throw CaseFailure(message: "kg per day: \(String(describing: lines[0].result))")
        }
        guard r84IsError(lines[1]) else {
            throw CaseFailure(message: "bare number at: \(String(describing: lines[1].result))")
        }
    },
    EngineCase("r84-rate-not-stolen") {
        // `10 km in m` stays a unit conversion (unit-only target);
        // `90 km / 3 day` stays mixed algebra (both already green
        // elsewhere — the rate phrase must not swallow either).
        let lines = r84Sheet("10 km in m\n90 km / 3 day")
        try r84Close(r84Value(lines[0]), 10000, "10 km in m")
        try r84Close(r84Value(lines[1]), 30, "90 km / 3 day")
        guard r84Unit(lines[1]) == "km/day" else {
            throw CaseFailure(message: "km/day: \(String(describing: r84Unit(lines[1])))")
        }
    },
]
public let r84UnitUiCases: [EngineCase] = []
// MARK: R84: syntax paint + context isolation

public let r84SyntaxCases: [EngineCase] = [
    EngineCase("r84-paint-mixed-line") {
        // `1 km + 1000 m` paints the quantities (number role), the
        // unit words (conversion role) and the operator.
        let rows = SyntaxClassifier.spans(for: "1 km + 1000 m", rates: Rates(),
                                          decimalPlaces: 10)
        let spans = rows[0]
        func has(_ role: SyntaxRole, _ text: String, _ full: String) -> Bool {
            let loc = (full as NSString).range(of: text).location
            return spans.contains { $0.role == role && $0.range.location == loc }
        }
        guard has(.number, "1", "1 km + 1000 m") else {
            throw CaseFailure(message: "km number span: \(spans)")
        }
        guard has(.conversion, "km", "1 km + 1000 m") else {
            throw CaseFailure(message: "km unit span: \(spans)")
        }
        guard has(.number, "1000", "1 km + 1000 m") else {
            throw CaseFailure(message: "1000 span: \(spans)")
        }
        // `m` at position 12 (the unit word, not the `m` inside `km`).
        guard spans.contains(where: { $0.role == .conversion && $0.range.location == 12 && $0.range.length == 1 })
        else {
            throw CaseFailure(message: "m span: \(spans)")
        }
    },
    EngineCase("r84-paint-custom-unit") {
        // A custom unit name paints like a known unit word.
        let rows = [UserUnitDefinition(name: "zorch", definition: "660 feet")]
        let res = UnitResolver.resolve(rows)
        let out = SyntaxClassifier.spans(for: "10 zorch to m", rates: Rates(),
                                         decimalPlaces: 10,
                                         unitContext: res.context)
        let spans = out[0]
        let loc = ("10 zorch to m" as NSString).range(of: "zorch").location
        guard spans.contains(where: { $0.role == .conversion && $0.range.location == loc })
        else {
            throw CaseFailure(message: "zorch span: \(spans)")
        }
    },
    EngineCase("r84-paint-ppi-line") {
        // The PPI phrase paints its numbers, the px unit and the
        // grammar keywords through the mixed painter.
        let out = SyntaxClassifier.spans(for: "1 cm in px at 326 ppi",
                                         rates: Rates(), decimalPlaces: 10)
        let spans = out[0]
        let pxLoc = ("1 cm in px at 326 ppi" as NSString).range(of: "px").location
        guard spans.contains(where: { $0.role == .conversion && $0.range.location == pxLoc })
        else {
            throw CaseFailure(message: "px span: \(spans)")
        }
    },
    EngineCase("r84-context-per-pass") {
        // The unit context is PER EVALUATION PASS: the same content
        // with a custom context resolves the custom unit; the same
        // content through the built-in context never sees it (no
        // mutable global leaks across passes).
        let rows = [UserUnitDefinition(name: "zorch", definition: "660 feet")]
        let res = UnitResolver.resolve(rows)
        let with = r84Sheet("10 zorch", unitContext: res.context)
        try r84Close(r84Value(with[0]), 10, "10 zorch (custom pass)")
        guard r84Unit(with[0]) == "zorch" else {
            throw CaseFailure(message: "unit: \(String(describing: r84Unit(with[0])))")
        }
        // The built-in pass never sees `zorch`: the line is NOT
        // shape-owned there (no quantity literal), so the pre-R84
        // word-strip fallback reads the bare number — custom units
        // cannot leak between passes.
        let without = r84Sheet("10 zorch")
        try r84Close(r84Value(without[0]), 10, "10 zorch (built-in pass strips the word)")
        guard r84Unit(without[0]) == nil else {
            throw CaseFailure(message: "unit: \(String(describing: r84Unit(without[0])))")
        }
    },
    EngineCase("r84-quantity-never-persisted") {
        // Quantity VALUES live only in the evaluation pass: the sheet
        // model (content, line IDs, references) carries no computed
        // quantities, and .nlx exports embed no unit state.
        let lines = r84Sheet("1 km + 2 km\n90 km / 3 day")
        _ = lines
        // Re-evaluating the SAME content is deterministic and
        // self-contained (no snapshot feeds the second pass).
        let again = r84Sheet("1 km + 2 km\n90 km / 3 day")
        try r84Close(r84Value(again[0]), 3, "pass 2 value 1")
        try r84Close(r84Value(again[1]), 30, "pass 2 value 2")
        guard r84Unit(again[1]) == "km/day" else {
            throw CaseFailure(message: "rate: \(String(describing: r84Unit(again[1])))")
        }
    },
]
let M84 = String(answerTokenMarker)

public let r84TokenFormattingCases: [EngineCase] = [
    EngineCase("r84-token-quantity-display") {
        let u0 = UUID(), u1 = UUID()
        let content = "1 km + 2 km\n\(M84)"
        let (lines, tokens) = resolveSheet(
            content: content, lineIDs: [u0, u1],
            references: [AnswerReference(sourceLineID: u0, labelLine: 1, location: 12)],
            rates: Rates(), decimalPlaces: 7)
        guard case .active(let v, let unit, let display) = tokens[0].state else {
            throw CaseFailure(message: "token state: \(tokens[0].state)")
        }
        try r84Close(v, 3, "token value")
        guard unit == "km" else { throw CaseFailure(message: "token unit: \(String(describing: unit))") }
        guard display == "3 km" else { throw CaseFailure(message: "token display: \(display)") }
        // The bare token line shows the full referenced quantity.
        if case .number(let lv, let lu, _, _) = lines[1].result {
            try r84Close(lv, 3, "token line value")
            guard lu == "km" else { throw CaseFailure(message: "token line unit: \(String(describing: lu))") }
        } else {
            throw CaseFailure(message: "token line: \(String(describing: lines[1].result))")
        }
    },
    EngineCase("r84-token-quantity-algebra") {
        // Token-to-token unit algebra works through the shared quantity
        // rules (`TOKEN + TOKEN` same-unit sum); a UNIT LITERAL on the
        // plain side of a token expression is outside the token grammar
        // (named quantities cover that: `x = 1 km + 2 km`, `x + 500 m`).
        let u0 = UUID(), u1 = UUID(), u2 = UUID()
        let content = "1 km + 2 km\n1 km\n\(M84) + \(M84)"
        let (lines, tokens) = resolveSheet(
            content: content, lineIDs: [u0, u1, u2],
            references: [AnswerReference(sourceLineID: u0, labelLine: 2, location: 17),
                        AnswerReference(sourceLineID: u1, labelLine: 2, location: 21)],
            rates: Rates(), decimalPlaces: 7)
        try r84Close(r84Value(lines[2]), 4, "TOKEN(3 km) + TOKEN(1 km)")
        guard r84Unit(lines[2]) == "km" else {
            throw CaseFailure(message: "unit: \(String(describing: r84Unit(lines[2])))")
        }
        _ = tokens
        // The unit-literal form is a strict error, never a word strip.
        let a0 = UUID(), a1 = UUID()
        let (l2, _) = resolveSheet(
            content: "1 km + 2 km\n\(M84) + 500 m",
            lineIDs: [a0, a1],
            references: [AnswerReference(sourceLineID: a0, labelLine: 1, location: 12)],
            rates: Rates(), decimalPlaces: 7)
        guard r84IsError(l2[1]) else {
            throw CaseFailure(message: "unit literal in token expr: \(String(describing: l2[1].result))")
        }
    },
    EngineCase("r84-token-conversion") {
        // `TOKEN to m` — the same conversion engine a plain line uses.
        let u0 = UUID(), u1 = UUID()
        let content = "1 km + 2 km\n\(M84) to m"
        let (lines, tokens) = resolveSheet(
            content: content, lineIDs: [u0, u1],
            references: [AnswerReference(sourceLineID: u0, labelLine: 1, location: 12)],
            rates: Rates(), decimalPlaces: 7)
        _ = tokens
        try r84Close(r84Value(lines[1]), 3000, "TOKEN to m")
        guard r84Unit(lines[1]) == "m" else {
            throw CaseFailure(message: "m unit: \(String(describing: r84Unit(lines[1])))")
        }
    },
    EngineCase("r84-token-custom-unit") {
        // A token whose source line carries a CUSTOM unit label: the
        // label resolves through the per-pass context for the `to`
        // conversion and the copy/display text.
        let rows = [UserUnitDefinition(name: "zorch", definition: "660 feet")]
        let res = UnitResolver.resolve(rows)
        let u0 = UUID(), u1 = UUID()
        let content = "10 zorch\n\(M84) to m"
        let (lines, tokens) = resolveSheet(
            content: content, lineIDs: [u0, u1],
            references: [AnswerReference(sourceLineID: u0, labelLine: 1, location: 9)],
            rates: Rates(), decimalPlaces: 7,
            unitContext: res.context)
        guard case .active(let v, let unit, let display) = tokens[0].state else {
            throw CaseFailure(message: "token state: \(tokens[0].state)")
        }
        try r84Close(v, 10, "token value")
        guard unit == "zorch" else { throw CaseFailure(message: "token unit: \(String(describing: unit))") }
        guard display == "10 zorch" else { throw CaseFailure(message: "token display: \(display)") }
        try r84Close(r84Value(lines[1]), 2011.68, "TOKEN to m (custom label)")
        guard r84Unit(lines[1]) == "m" else {
            throw CaseFailure(message: "m unit: \(String(describing: r84Unit(lines[1])))")
        }
    },
    EngineCase("r84-copy-shows-unit") {
        // The copyable/visible text of a unit answer is value + label:
        // the display formatter renders `3 km`, never a bare 3.
        let lines = r84Sheet("1 km + 2 km")
        let text = AnswerDisplay.text(for: lines[0].result, decimalPlaces: 2)
        guard text == "3 km" else {
            throw CaseFailure(message: "display text: \(text ?? "nil")")
        }
    },
]
