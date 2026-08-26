import Foundation

// MARK: - Result rounding

func roundResult(_ value: Double, decimalPlaces: Int) -> Double {
    // Defense in depth: the engine boundaries reject non-finite results,
    // so this is a pure pass-through safety valve. Without it,
    // String(format:) would emit "inf"/"nan" and Double("inf") would
    // smuggle a non-finite value back into a .number result.
    guard value.isFinite else { return value }
    if value.truncatingRemainder(dividingBy: 1) != 0 {
        // Fixed-point rounding only makes sense inside the range it can
        // represent; sub-1e-9 magnitudes (eV, ...) pass through intact.
        guard abs(value) >= 1e-9, abs(value) < 1e15 else { return value }
        let factor = pow(10.0, Double(decimalPlaces))
        // use formatted to avoid floating noise
        let s = String(format: "%.\(decimalPlaces)f", value)
        if let d = Double(s) { return d }
        return (value * factor).rounded() / factor
    }
    return value
}

// MARK: - Conversion shape

/// The detected `<number> <unit> to|in <unit>` shape of a line, with
/// UTF-16 ranges for syntax highlighting.
///
/// Generalization from r16: the keyword is exactly one whitespace-
/// delimited `to` OR `in` (case-insensitive), and the number may carry
/// a currency symbol source (`$3,740.00 in EUR`, `€100 to USD`) in
/// which case the from side may be EMPTY (the symbol implies the
/// source currency). When a bare `in` would collide with the inch unit
/// (`3 in to cm`), the `to` keyword wins and `in` stays a unit word.
struct ConversionShape: Equatable {
    let numberText: String
    let fromText: String?
    let toText: String
    let numberRange: NSRange
    let fromRange: NSRange?
    let toRange: NSRange
    let symbolRange: NSRange?
    let symbolCode: String?
}

private let conversionNumberPattern = try? NSRegularExpression(
    pattern: #"^[+-]?(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?(?:[eE][+-]?\d+)?"#)

/// Matches a leading currency symbol source: the marker must be glued
/// to a following digit or `.` (`$3,740.00`, `€100`), so prose like
/// `the $ sign` never matches.
private let conversionSymbolPattern = try? NSRegularExpression(
    pattern: "^(?:" + CurrencyPresentation.inputMarkerPattern + ")(?=[0-9.])")

/// Detects `<symbol?> <number> <fromUnit?> to|in <toUnit>` per the
/// `ConversionShape` documentation. Returns nil otherwise; the line
/// then flows on (money layer, date layer, expression evaluator).
func conversionShape(_ line: String) -> ConversionShape? {
    let ns = line as NSString
    let lower = (ns as String).lowercased() as NSString
    // Count whitespace-delimited `to` and `in` keywords and pick the
    // conversion keyword.
    var toRanges: [NSRange] = []
    var inRanges: [NSRange] = []
    func collect(_ kw: String, into: inout [NSRange]) {
        var start = 0
        while start <= ns.length {
            let r = lower.range(of: " \(kw) ",
                                range: NSRange(location: start,
                                               length: ns.length - start))
            guard r.location != NSNotFound else { break }
            into.append(r)
            start = r.location + r.length
        }
    }
    collect("to", into: &toRanges)
    collect("in", into: &inRanges)
    var kwRange: NSRange?
    if toRanges.count == 1, inRanges.isEmpty {
        kwRange = toRanges[0]
    } else if inRanges.count == 1, toRanges.isEmpty {
        kwRange = inRanges[0]
    } else if toRanges.count == 1, !inRanges.isEmpty,
              inRanges.allSatisfy({ $0.location < toRanges[0].location }) {
        // `3 in to cm`: `in` is the inch unit, `to` is the keyword.
        kwRange = toRanges[0]
    }
    guard let toR = kwRange else { return nil }
    // A leading currency symbol source (optional).
    var symbolRange: NSRange?
    var symbolCode: String?
    if let symRe = conversionSymbolPattern,
       let sM = symRe.firstMatch(in: line as String,
                                 range: NSRange(location: 0, length: ns.length)) {
        symbolRange = sM.range
        symbolCode = CurrencyPresentation.code(forMarker: ns.substring(with: sM.range))
    }
    // The number must start the line (right after the symbol, if any).
    let numberOrigin = symbolRange.map { $0.location + $0.length } ?? 0
    guard let numM = conversionNumberPattern?.firstMatch(
        in: String(ns.substring(from: numberOrigin)),
        range: NSRange(location: 0, length: ns.length - numberOrigin)),
        numM.range.location == 0 else { return nil }
    let numRange = NSRange(location: numM.range.location + numberOrigin,
                           length: numM.range.length)
    // A whitespace must separate number and unit text.
    let afterNum = numRange.location + numRange.length
    guard afterNum < ns.length,
          isWhitespace16(ns.character(at: afterNum)) else { return nil }
    // The keyword RANGE includes its surrounding spaces; the keyword
    // word itself sits one inside, so use the word boundaries for the
    // from/to split (a symbol source may leave the from side empty).
    let kwStart = toR.location + 1
    let kwEnd = toR.location + 1 + (toR.length - 2)
    guard symbolCode != nil || kwStart > afterNum else { return nil }
    let fromRaw = ns.substring(with: NSRange(location: afterNum, length: kwStart - afterNum))
    let fromText = fromRaw.trimmingCharacters(in: .whitespaces)
    // The from side may be empty ONLY when a symbol supplies the source.
    guard symbolCode != nil || fromText.containsLetter else { return nil }
    let toStart = kwEnd
    let toRaw = ns.substring(from: toStart)
    let toText = toRaw.trimmingCharacters(in: .whitespaces)
    guard toText.containsLetter else { return nil }
    // Ranges of the TRIMMED texts (spans must cover the unit words only).
    let fromRange = fromText.isEmpty ? nil
        : trimmedRange(of: fromText, in: fromRaw, origin: afterNum)
    let toRange = trimmedRange(of: toText, in: toRaw, origin: toStart)
    guard fromRange != nil || fromText.isEmpty, toRange != nil else { return nil }
    return ConversionShape(
        numberText: ns.substring(with: numRange),
        fromText: fromText.isEmpty ? nil : fromText,
        toText: toText,
        numberRange: numRange,
        fromRange: fromRange,
        toRange: toRange!,
        symbolRange: symbolRange,
        symbolCode: symbolCode
    )
}

private func isWhitespace16(_ c: UInt16) -> Bool {
    c == 0x20 || c == 0x09
}

private extension String {
    var containsLetter: Bool { contains { $0.isLetter } }
}

/// The NSRange of `text` inside `raw` (same string content up to
/// trimmed edges), offset by `origin`.
private func trimmedRange(of text: String, in raw: String, origin: Int) -> NSRange? {
    guard let r = raw.range(of: text) else { return nil }
    // The unit text is unique within its side of the line, so the first
    // occurrence is the right one.
    let ns = NSRange(r, in: raw)
    return NSRange(location: origin + ns.location, length: ns.length)
}

// MARK: - The single conversion engine

/// Converts `value` from `from` into `to` through ONE declared
/// finite-transform rule per class:
/// - temperature: affine kelvin round-trip (finite for all finite in);
/// - currency: the live rate table (nil rate -> no conversion);
/// - fuel: L/m consumption round-trip, economy and consumption forms
///   never mix;
/// - linear: value × fromFactor / toFactor, same vector AND family.
/// Returns nil when the pair is unsupported or the result is not
/// finite.
public func convertValue(_ value: Double,
                         from: UnitExpr,
                         to: UnitExpr,
                         rates: Rates) -> (value: Double, unit: String)? {
    // Same unit both sides: exact identity, no floating round-trip error.
    if from.kind == to.kind, from.vector == to.vector,
       from.family == to.family, from.toBase == to.toBase {
        return (value, to.label)
    }
    switch (from.kind, to.kind) {
    case (.temperature(let fu), .temperature(let tu)):
        let v = tu.fromKelvin(fu.toKelvin(value))
        guard v.isFinite else { return nil }
        return (v, to.label)
    case (.temperature, _), (_, .temperature):
        return nil
    case (.currency(let fc), .currency(let tc)):
        if fc == tc { return (value, to.label) }
        guard let r = rates.rate(from: fc, to: tc) else { return nil }
        let v = value * r
        guard v.isFinite else { return nil }
        return (v, to.label)
    case (.currency, _), (_, .currency):
        return nil
    case (.fuel(let ff, let fr), .fuel(let tf, let tr)):
        // Consumption (L/m): economy forms are reciprocal; crossing
        // between the two classes is the true reciprocal of the value.
        let consumption = fr ? 1.0 / (value * ff) : value * ff
        guard consumption.isFinite, consumption > 0 else { return nil }
        let out = tr ? 1.0 / (consumption * tf) : consumption / tf
        guard out.isFinite else { return nil }
        return (out, to.label)
    case (.fuel, _), (_, .fuel):
        return nil
    case (.factor, .factor):
        guard from.isLinear, to.isLinear,
              from.vector == to.vector, from.family == to.family,
              to.toBase.isFinite, to.toBase > 0 else { return nil }
        let v = value * from.toBase / to.toBase
        guard v.isFinite else { return nil }
        return (v, to.label)
    }
}

// MARK: - Line conversion entry point

/// Evaluates a line of the shape `<number> <unit> to <unit>`:
/// temperatures, currencies (live rates), fuel economy and measurement
/// units all flow through the single `convertValue` engine. A line that
/// MATCHES the shape but cannot be converted — incompatible quantities,
/// a word that is not a known unit, an unavailable rate — returns a
/// GENERIC ERROR instead of falling through to the expression
/// evaluator (which would silently return the leading number). Anything
/// not matching the shape returns `nil` and keeps flowing into the
/// assignment/expression evaluation.
func tryConversion(_ line: String, rates: Rates, decimalPlaces: Int) -> LineResult? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard let shape = conversionShape(trimmed) else { return nil }
    // Commas are grouping separators in the number.
    let numText = shape.numberText.replacingOccurrences(of: ",", with: "")
    guard let num = Double(numText) else { return .error(message: "Invalid number") }
    guard num.isFinite else { return .error(message: "Invalid number") }
    // From side: an explicit unit expression, or the currency implied
    // by a leading symbol source (`$100 to EUR`, `€100 in USD`).
    var from: UnitCatalog.ParsedExpr
    if let code = shape.symbolCode {
        guard let symUnit = UnitCatalog.resolveExpression(code) else {
            return .error(message: "Unknown units")
        }
        if let fromText = shape.fromText {
            guard let explicit = UnitCatalog.resolveExpression(fromText) else {
                return .error(message: "Unknown units")
            }
            // A text source must agree with the symbol's currency.
            guard case .currency(let ec) = explicit.unit.kind,
                  ec.caseInsensitiveCompare(code) == .orderedSame else {
                return .error(message: "Incompatible units")
            }
        }
        from = symUnit
    } else {
        guard let fromText = shape.fromText,
              let resolved = UnitCatalog.resolveExpression(fromText) else {
            return .error(message: "Unknown units")
        }
        from = resolved
    }
    guard let to = UnitCatalog.resolveExpression(shape.toText) else {
        return .error(message: "Unknown units")
    }
    if let (v, unit) = convertValue(num, from: from.unit, to: to.unit, rates: rates) {
        // Conversion results keep full precision (up to 10 decimals) so
        // exact factors like 1 gal = 3.785411784 L survive the round.
        return .number(value: roundResult(v, decimalPlaces: max(decimalPlaces, 10)), unit: unit)
    }
    // Shape matched, conversion impossible: distinguish the missing-rate
    // case (both sides currencies, no table entry) from plain
    // incompatibility.
    if case .currency = from.unit.kind, case .currency = to.unit.kind {
        return .error(message: "Rates unavailable")
    }
    return .error(message: "Incompatible units")
}

// MARK: - Quantity helpers (shared by reference tokens)

/// Resolves a DISPLAY unit label (the `unit` carried by a `.number`
/// result, e.g. `m`, `kg`, `C°`, `USD`, `km/h`) back to its unit
/// expression. Returns nil for labels no unit owns.
public func unitExpr(byLabel label: String) -> UnitExpr? {
    UnitCatalog.resolveLabel(label)
}

/// Whether two display unit labels name the same quantity kind: both
/// nil (unitless), identical case-insensitively, or both labels of
/// quantities that the engine can convert WITHOUT extra context
/// (same linear vector+family, or both temperature / both currency /
/// both fuel forms of the same direction).
public func sameQuantityUnit(_ a: String?, _ b: String?) -> Bool {
    if a == nil && b == nil { return true }
    guard let a, let b else { return false }
    if a.caseInsensitiveCompare(b) == .orderedSame { return true }
    guard let ea = unitExpr(byLabel: a), let eb = unitExpr(byLabel: b) else { return false }
    return quantityKindsMatch(ea, eb)
}

/// Class-level compatibility of two unit expressions.
public func quantityKindsMatch(_ a: UnitExpr, _ b: UnitExpr) -> Bool {
    switch (a.kind, b.kind) {
    case (.temperature, .temperature):
        return true
    case (.currency, .currency):
        return true
    case (.fuel(_, let ra), .fuel(_, let rb)):
        return ra == rb
    case (.factor, .factor):
        guard a.isLinear, b.isLinear else { return false }
        return a.vector == b.vector && a.family == b.family
    default:
        return false
    }
}

/// Converts a value between two display labels (identical labels are a
/// no-op). Currency needs no rate table here, so currency pairs return
/// nil — token arithmetic never converts money; the `<token> to <unit>`
/// grammar does (it has the table). Returns nil for anything the engine
/// cannot convert or that is not finite.
public func convertQuantityUnit(_ value: Double, fromLabel: String, toLabel: String) -> Double? {
    if fromLabel.caseInsensitiveCompare(toLabel) == .orderedSame { return value }
    guard let from = unitExpr(byLabel: fromLabel),
          let to = unitExpr(byLabel: toLabel) else { return nil }
    return convertValue(value, from: from, to: to, rates: Rates())?.value
}

/// Converts a token quantity (the current result of its referenced line,
/// carrying a display unit label) into the target unit expression of a
/// `<token> to <unit>` line — the SAME engine the
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
    guard let from = unitExpr(byLabel: fromLabel),
          let toExpr = UnitCatalog.resolveExpression(to) else { return nil }
    return convertValue(value, from: from, to: toExpr.unit, rates: rates)
}
