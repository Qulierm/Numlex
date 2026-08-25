import Foundation

/// One measurement unit: which dimension it belongs to, how many base
/// units of that dimension one of it equals, and the canonical output
/// label for a result expressed in it. Aliases (symbol, short word,
/// plural) resolve to the SAME definition, so both sides of a
/// `<number> <from> to <to>` line are looked up independently.
private struct UnitDef: Sendable {
    let dimension: String
    let baseFactor: Double
    let label: String
}

/// Measurement unit table. Base units: meter, kilogram, liter.
///
/// Labels preserve the legacy output conventions where users rely on
/// them (spelled-out `meter(s)` reports `meters`, `teaspoon(s)` reports
/// `teaspoons`, `t`/`ton` reports `ton`), while the short aliases report
/// their canonical symbol (`km to m` reports `m`, not `meters`).
private let units: [String: UnitDef] = {
    var m: [String: UnitDef] = [:]
    func add(_ alias: String, _ dimension: String, _ factor: Double, _ label: String) {
        m[alias] = UnitDef(dimension: dimension, baseFactor: factor, label: label)
    }
    // Length — base: meter
    add("mm", "length", 0.001, "mm")
    add("millimeter", "length", 0.001, "mm")
    add("millimeters", "length", 0.001, "mm")
    add("cm", "length", 0.01, "cm")
    add("centimeter", "length", 0.01, "cm")
    add("centimeters", "length", 0.01, "cm")
    add("m", "length", 1, "m")
    add("meter", "length", 1, "meters")
    add("meters", "length", 1, "meters")
    add("km", "length", 1000, "km")
    add("kilometer", "length", 1000, "km")
    add("kilometers", "length", 1000, "km")
    add("mi", "length", 1609.34, "mi")
    add("mile", "length", 1609.34, "miles")
    add("miles", "length", 1609.34, "miles")
    // Mass — base: kilogram
    add("mg", "mass", 1e-6, "mg")
    add("milligram", "mass", 1e-6, "mg")
    add("milligrams", "mass", 1e-6, "mg")
    add("g", "mass", 1e-3, "g")
    add("gram", "mass", 1e-3, "g")
    add("grams", "mass", 1e-3, "g")
    add("kg", "mass", 1, "kg")
    add("kilogram", "mass", 1, "kg")
    add("kilograms", "mass", 1, "kg")
    add("t", "mass", 1000, "ton")
    add("ton", "mass", 1000, "ton")
    add("tons", "mass", 1000, "ton")
    // Volume — base: liter
    add("ml", "volume", 0.001, "ml")
    add("milliliter", "volume", 0.001, "ml")
    add("milliliters", "volume", 0.001, "ml")
    add("l", "volume", 1, "L")
    add("liter", "volume", 1, "L")
    add("liters", "volume", 1, "L")
    add("tsp", "volume", 0.005, "tsp")
    add("teaspoon", "volume", 0.005, "teaspoons")
    add("teaspoons", "volume", 0.005, "teaspoons")
    return m
}()

/// Temperature pairs are NOT dimension-factor based: each supported
/// direction has its own transform and output label. Keyed by the
/// lowercased `<from> to <to>` word pair, exactly like the legacy map.
private struct TempDef: Sendable {
    let fn: @Sendable (Double) -> Double
    let label: String
}
private let temps: [String: TempDef] = [
    "f to c": TempDef(fn: { ($0 - 32) * 5/9 }, label: "C°"),
    "c to f": TempDef(fn: { $0 * 1.8 + 32 }, label: "F°"),
    "k to c": TempDef(fn: { $0 - 273.15 }, label: "C°"),
    "c to k": TempDef(fn: { $0 + 273.15 }, label: "K°"),
]

func roundResult(_ value: Double, decimalPlaces: Int) -> Double {
    // Defense in depth: the engine boundaries reject non-finite results,
    // so this is a pure pass-through safety valve. Without it,
    // String(format:) would emit "inf"/"nan" and Double("inf") would
    // smuggle a non-finite value back into a .number result.
    guard value.isFinite else { return value }
    if value.truncatingRemainder(dividingBy: 1) != 0 {
        let factor = pow(10.0, Double(decimalPlaces))
        // use formatted to avoid floating noise
        let s = String(format: "%.\(decimalPlaces)f", value)
        if let d = Double(s) { return d }
        return (value * factor).rounded() / factor
    }
    return value
}

/// Evaluates a line of the shape `<signed number> <unit> to <unit>`:
/// temperatures first (custom transforms), then currency pairs (rates),
/// then measurement units resolved independently through their
/// dimension base. A line that MATCHES the shape but cannot be
/// converted — incompatible dimensions, or a word that is not a known
/// unit for this pair kind — returns a GENERIC ERROR instead of falling
/// through to the expression evaluator (which would silently return the
/// leading number). Anything not matching the shape returns `nil` and
/// keeps flowing into the assignment/expression evaluation.
func tryConversion(_ line: String, rates: Rates, decimalPlaces: Int) -> LineResult? {
    // One parse for everything: commas are grouping separators in the
    // leading number and may not split the unit words.
    let trimmedCommas = line.trimmingCharacters(in: .whitespaces)
        .replacingOccurrences(of: ",", with: "")
    guard let regex = try? NSRegularExpression(
        pattern: #"^([+-]?\d*\.?\d+)\s+(\w+)\s+to\s+(\w+)$"#,
        options: .caseInsensitive) else { return nil }
    let ns = trimmedCommas as NSString
    guard let match = regex.firstMatch(in: trimmedCommas,
                                       range: NSRange(location: 0, length: ns.length)),
          match.numberOfRanges == 4,
          let num = Double(ns.substring(with: match.range(at: 1))) else { return nil }
    let from = ns.substring(with: match.range(at: 2)).lowercased()
    let to = ns.substring(with: match.range(at: 3)).lowercased()
    let key = "\(from) to \(to)"
    // A conversion-shaped line whose number has hundreds of digits
    // parses to ±∞: it is a conversion attempt with an unusable number,
    // so it gets the generic hidden error instead of a fallthrough.
    guard num.isFinite else { return .error(message: "Invalid number") }

    // 1. Temperature: custom transform per supported direction. The
    //    input and the transformed result must stay finite.
    if let temp = temps[key] {
        let t = temp.fn(num)
        guard t.isFinite else { return .error(message: "Overflow") }
        return .number(value: roundResult(t, decimalPlaces: decimalPlaces),
                       unit: temp.label)
    }
    // 2. Currency: the six supported pairs and their rate lookups.
    //    A recognized pair without loaded rates is a rates error; an
    //    unrecognized pair falls through to the unit table below, where
    //    its words are (correctly) unknown units.
    var value: Double?
    var unit: String?
    switch key {
    case "usd to rub":
        guard let r = rates.USD else { return .error(message: "Rates unavailable") }
        value = num * r; unit = "RUB"
    case "eur to rub":
        guard let r = rates.EUR else { return .error(message: "Rates unavailable") }
        value = num * r; unit = "RUB"
    case "rub to eur":
        guard let r = rates.EUR else { return .error(message: "Rates unavailable") }
        value = num / r; unit = "EUR"
    case "usd to eur":
        guard let r = rates.EURUSD else { return .error(message: "Rates unavailable") }
        value = num * r; unit = "EUR"
    case "eur to usd":
        guard let r = rates.EURUSD else { return .error(message: "Rates unavailable") }
        value = num / r; unit = "USD"
    case "rub to usd":
        guard let r = rates.USD else { return .error(message: "Rates unavailable") }
        value = num / r; unit = "usd"
    default:
        break
    }
    if let v = value {
        // Non-finite rates (∞/NaN) or overflow must become a generic
        // hidden error, never a .number.
        guard v.isFinite else { return .error(message: "Overflow") }
        return .number(value: roundResult(v, decimalPlaces: decimalPlaces), unit: unit)
    }
    // 3. Measurement units: both aliases must resolve and share a
    //    dimension; the result goes through the base unit.
    if let fromUnit = units[from], let toUnit = units[to] {
        guard fromUnit.dimension == toUnit.dimension else {
            return .error(message: "Incompatible units")
        }
        let result = num * fromUnit.baseFactor / toUnit.baseFactor
        // Large FINITE results (e.g. 5e22) are perfectly valid and keep
        // flowing to the scientific display; only non-finite overflow is
        // rejected.
        guard result.isFinite else { return .error(message: "Overflow") }
        return .number(value: roundResult(result, decimalPlaces: decimalPlaces),
                       unit: toUnit.label)
    }
    return .error(message: "Unknown units")
}

// MARK: - Quantity helpers (shared by reference tokens)

/// Resolves a DISPLAY unit label (the `unit` carried by a `.number`
/// result, e.g. `meters`, `m`, `kg`, `ton`, `L`) back to its unit
/// definition. Returns nil for temperature/currency labels, which are
/// not dimension-factor based.
public func unitDefinition(byLabel label: String) -> (dimension: String, baseFactor: Double)? {
    let key = label.lowercased()
    for def in units.values where def.label.lowercased() == key {
        return (def.dimension, def.baseFactor)
    }
    return nil
}

/// Whether two display unit labels name the same quantity kind: both
/// nil (unitless), identical case-insensitively, or both measurement
/// labels of the SAME dimension. Temperature and currency labels match
/// only when identical (there is no factor-based conversion between
/// them in the quantity rules).
public func sameQuantityUnit(_ a: String?, _ b: String?) -> Bool {
    if a == nil && b == nil { return true }
    guard let a, let b else { return false }
    if a.caseInsensitiveCompare(b) == .orderedSame { return true }
    if let da = unitDefinition(byLabel: a)?.dimension,
       let db = unitDefinition(byLabel: b)?.dimension {
        return da == db
    }
    return false
}

/// Converts a value between two measurement display labels of the same
/// dimension (identical labels are a no-op). Returns nil for pairs that
/// are not both factor-based measurement units.
public func convertQuantityUnit(_ value: Double, fromLabel: String, toLabel: String) -> Double? {
    if fromLabel.caseInsensitiveCompare(toLabel) == .orderedSame { return value }
    guard let from = unitDefinition(byLabel: fromLabel),
          let to = unitDefinition(byLabel: toLabel),
          from.dimension == to.dimension else { return nil }
    let v = value * from.baseFactor / to.baseFactor
    return v.isFinite ? v : nil
}

/// Converts a token quantity (the current result of its referenced line,
/// carrying a display unit label) into the target unit word of a
/// `<token> to <unit>` line — the SAME tables and rate lookups the
/// `<number> <from> to <to>` grammar uses. Returns the unrounded value
/// and the canonical target label, or nil when the token has no unit or
/// the pair is unsupported (the caller then reports the generic hidden
/// error).
public func convertTokenQuantity(
    value: Double,
    fromLabel: String?,
    to: String,
    rates: Rates
) -> (value: Double, unit: String)? {
    guard let fromLabel else { return nil }
    let toLower = to.lowercased()
    // 1. Temperature: the result labels C°/F°/K° map to the c/f/k
    //    symbols the temperature table is keyed by.
    let tempSym: [String: String] = ["c°": "c", "f°": "f", "k°": "k"]
    if let sym = tempSym[fromLabel.lowercased()] {
        guard let t = temps["\(sym) to \(toLower)"] else { return nil }
        let r = t.fn(value)
        guard r.isFinite else { return nil }
        return (r, t.label)
    }
    // 2. Currency: the result labels RUB/EUR/USD/usd map to the rub/eur/
    //    usd codes the rate pairs are keyed by.
    let curSym: [String: String] = ["rub": "rub", "eur": "eur", "usd": "usd"]
    if let code = curSym[fromLabel.lowercased()] {
        let key = "\(code) to \(toLower)"
        switch key {
        case "usd to rub":
            guard let r = rates.USD else { return nil }
            let v = value * r; return v.isFinite ? (v, "RUB") : nil
        case "eur to rub":
            guard let r = rates.EUR else { return nil }
            let v = value * r; return v.isFinite ? (v, "RUB") : nil
        case "rub to eur":
            guard let r = rates.EUR, r != 0 else { return nil }
            let v = value / r; return v.isFinite ? (v, "EUR") : nil
        case "usd to eur":
            guard let r = rates.EURUSD else { return nil }
            let v = value * r; return v.isFinite ? (v, "EUR") : nil
        case "eur to usd":
            guard let r = rates.EURUSD, r != 0 else { return nil }
            let v = value / r; return v.isFinite ? (v, "USD") : nil
        case "rub to usd":
            guard let r = rates.USD, r != 0 else { return nil }
            let v = value / r; return v.isFinite ? (v, "usd") : nil
        default:
            return nil
        }
    }
    // 3. Measurement: the token's label resolves to a unit definition
    //    and the target word is an alias; the result uses the target's
    //    canonical label (same rule as the plain conversion grammar).
    guard let from = unitDefinition(byLabel: fromLabel),
          let toDef = units[toLower] else { return nil }
    guard from.dimension == toDef.dimension else { return nil }
    let v = value * from.baseFactor / toDef.baseFactor
    guard v.isFinite else { return nil }
    return (v, toDef.label)
}
