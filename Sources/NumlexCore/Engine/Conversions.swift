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

/// r73: scans the LEADING number of a conversion line under `context`.
/// Dot modes (legacy included) reproduce the old `conversionNumberPattern`
/// exactly: digits, optional `,`-thousands groups of EXACTLY three, an
/// optional `.decimal` tail, an optional exponent — `1,5` still scans as
/// `1` (two-digit "group" is a decimal, not a group). Decimal-comma modes
/// alternate well-formed group runs (the context's grouping separators —
/// a dot run counts as grouping ONLY with exactly three following digits,
/// so the in-progress `1.23` reads decimal) with the decimal separator,
/// and an optional exponent: `1.234,56` -> 1234.56, `1 234,5` -> 1234.5.
/// Returns the canonical number text and the number of UTF-16 units
/// consumed (the scan alphabet is BMP-only, so character offsets ==
/// UTF-16 offsets).
private func conversionNumber(_ s: String,
                              context: NumberFormatContext) -> (text: String, length: Int)? {
    let chars = Array(s)
    let n = chars.count
    func isDig(_ i: Int) -> Bool { i >= 0 && i < n && chars[i].isNumber }
    func threeDigitGroup(_ i: Int) -> Bool {
        // chars[i] is a grouping separator: exactly three digits follow,
        // then a non-digit (or end).
        guard isDig(i + 1), isDig(i + 2), isDig(i + 3) else { return false }
        if i + 4 < n, isDig(i + 4) { return false }
        return true
    }
    var i = 0
    if i < n, chars[i] == "+" || chars[i] == "-" { i += 1 }
    guard isDig(i) else { return nil }
    while i < n, isDig(i) { i += 1 }
    let groupChars: Set<Character> = {
        var set: Set<Character> = []
        func add(_ str: String) { str.unicodeScalars.forEach { set.insert(Character($0)) } }
        if context.decimalComma {
            add(context.groupingSeparator)
            context.inputGroupingSeparators.forEach(add)
        } else {
            set.insert(",")
        }
        return set
    }()
    let decimalChars: Set<Character> = context.decimalComma ? [".", ","] : ["."]
    while i < n {
        let c = chars[i]
        if c == ".", context.decimalComma, threeDigitGroup(i) {
            // A dot in decimal-comma mode is GROUPING only when the run
            // is exactly three digits; otherwise it is the decimal
            // point (the documented in-progress `1.23` rule).
            i += 4
            continue
        }
        if groupChars.contains(c), threeDigitGroup(i) {
            i += 4
            continue
        }
        if decimalChars.contains(c) {
            if i + 1 < n, isDig(i + 1) {
                i += 1
                while i < n, isDig(i) { i += 1 }
                continue
            }
            if i + 1 >= n { i += 1; continue } // bare trailing point: `1,`
            break
        }
        if c == "e" || c == "E" {
            var j = i + 1
            if j < n, chars[j] == "-" || chars[j] == "+" { j += 1 }
            if j < n, isDig(j) {
                i = j
                while i < n, isDig(i) { i += 1 }
                continue
            }
        }
        break
    }
    var span = String(chars[0..<i])
    // Canonicalize: drop grouping separators, then any remaining comma is
    // the decimal point -> dot.
    for ch in groupChars { span = span.replacingOccurrences(of: String(ch), with: "") }
    span = span.replacingOccurrences(of: ",", with: ".")
    guard let v = Double(span), v.isFinite else { return nil }
    _ = v
    return (span, i)
}

/// Matches a leading currency symbol source: the marker must be glued
/// to a following digit or `.` (`$3,740.00`, `€100`), so prose like
/// `the $ sign` never matches.
private let conversionSymbolPattern = try? NSRegularExpression(
    pattern: "^(?:" + CurrencyPresentation.inputMarkerPattern + ")(?=[0-9.])")

/// Detects `<symbol?> <number> <fromUnit?> to|in <toUnit>` per the
/// `ConversionShape` documentation. Returns nil otherwise; the line
/// then flows on (money layer, date layer, expression evaluator).
func conversionShape(_ line: String,
                         context: NumberFormatContext = .legacy) -> ConversionShape? {
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
    // r73: scanned under the number context instead of the fixed
    // dot-decimal regex (the legacy scanner reproduces the old pattern
    // byte-for-byte).
    let numberOrigin = symbolRange.map { $0.location + $0.length } ?? 0
    let tail = String(ns.substring(from: numberOrigin))
    guard let scanned = conversionNumber(tail, context: context) else { return nil }
    let numRange = NSRange(location: numberOrigin, length: scanned.length)
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
/// The explicit conversion target, resolved against the evaluated SOURCE.
/// Ordinary unambiguous resolution wins; a documented contextual shorthand is
/// tried only when the ordinary reading is incompatible with the source.
private func conversionTarget(_ text: String, value: Double, from: UnitExpr,
                              unitContext: UnitContext, rates: Rates) -> UnitExpr? {
    let source = value.isFinite ? Quantity(value: value, display: from) : nil
    return UnitTargetResolver.resolve(text, source: source,
                                      unitContext: unitContext, rates: rates)
}

func tryConversion(_ line: String, rates: Rates, decimalPlaces: Int,
                   context: NumberFormatContext = .legacy,
                   unitContext: UnitContext = .builtIns) -> LineResult? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard let shape = conversionShape(trimmed, context: context) else { return nil }
    // r73: the number text is already context-scanned; re-canonicalize
    // with the same rules (grouping stripped, decimal comma -> dot).
    guard let scannedNum = conversionNumber(shape.numberText, context: context),
          let num = Double(scannedNum.text), num.isFinite else {
        return .error(message: "Invalid number")
    }
    // From side: an explicit unit expression, or the currency implied
    // by a leading symbol source (`$100 to EUR`, `€100 in USD`).
    var from: UnitCatalog.ParsedExpr
    if let code = shape.symbolCode {
        guard let symUnit = unitContext.resolveExpression(code) else {
            return .error(message: "Unknown units")
        }
        if let fromText = shape.fromText {
            guard let explicit = unitContext.resolveExpression(fromText) else {
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
              let resolved = unitContext.resolveExpression(fromText) else {
            return .error(message: "Unknown units")
        }
        from = resolved
    }
    // The target is chosen against the EVALUATED source quantity, so a
    // documented contextual shorthand (`ms` for a speed source) is read only
    // when the ordinary reading is incompatible with the source; the
    // ordinary, unambiguous resolution still wins whenever it fits.
    guard let targetUnit = conversionTarget(shape.toText, value: num, from: from.unit,
                                           unitContext: unitContext, rates: rates) else {
        return .error(message: "Unknown units")
    }
    let to = UnitCatalog.ParsedExpr(unit: targetUnit, def: nil, text: shape.toText)
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
public func unitExpr(byLabel label: String,
                     context: UnitContext = .builtIns) -> UnitExpr? {
    // r84: custom display labels resolve through the per-pass context
    // (which falls back to the built-in catalog).
    context.resolveLabel(label)
}

/// Whether two display unit labels name the same quantity kind: both
/// nil (unitless), identical case-insensitively, or both labels of
/// quantities that the engine can convert WITHOUT extra context
/// (same linear vector+family, or both temperature / both currency /
/// both fuel forms of the same direction).
public func sameQuantityUnit(_ a: String?, _ b: String?,
                             context: UnitContext = .builtIns) -> Bool {
    if a == nil && b == nil { return true }
    guard let a, let b else { return false }
    if a.caseInsensitiveCompare(b) == .orderedSame { return true }
    guard let ea = unitExpr(byLabel: a, context: context),
          let eb = unitExpr(byLabel: b, context: context) else { return false }
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
public func convertQuantityUnit(_ value: Double, fromLabel: String, toLabel: String,
                                context: UnitContext = .builtIns) -> Double? {
    if fromLabel.caseInsensitiveCompare(toLabel) == .orderedSame { return value }
    guard let from = unitExpr(byLabel: fromLabel, context: context),
          let to = unitExpr(byLabel: toLabel, context: context) else { return nil }
    return convertValue(value, from: from, to: to, rates: Rates())?.value
}

// MARK: - Linked-answer conversion bridge

/// r91: substitutes ONE leading linked value (an answer token) into an
/// ordinary conversion line so the linked answer participates in exactly
/// the same grammar a typed literal does — `<token> mg to kg` behaves
/// like `4673 mg to kg`.
///
/// This is an EVALUATION-COPY adapter only: the document is never
/// touched (no source text, marker, reference or line ID is rewritten).
/// The caller passes the ORIGINAL line, the UTF-16 location of the single
/// participating marker, the resolved canonical value and the display
/// unit label the linked answer already carries (nil for a unitless
/// answer). The bridge builds
///
///     <shortest round-trip literal>[ <carried unit>] <user's to|in suffix>
///
/// and hands that to `tryConversion` — the ONE conversion engine — so
/// target shorthand, the inch-vs-`in` disambiguation, error classes,
/// currency rates and conversion precision all match ordinary lines by
/// construction. Returns nil when the line is not this shape (so the
/// caller can fall through to its other routes); otherwise the
/// conversion result or its error.
///
/// The number is written with `String(value)` (shortest round-trip
/// decimal, never a grouped or rounded display string) and its decimal
/// point becomes `,` only in decimal-comma modes — a dot would otherwise
/// be read as a GROUPING separator there and silently change the value.
public func linkedConversionResult(
    line: String,
    markerAt: Int,
    value: Double,
    carriedUnit: String?,
    rates: Rates,
    decimalPlaces: Int,
    context: NumberFormatContext = .legacy,
    unitContext: UnitContext = .builtIns
) -> LineResult? {
    // The marker must be the FIRST non-whitespace content: the synthetic
    // line puts the number there, and the conversion grammar requires the
    // number to start the line.
    let ns = line as NSString
    guard markerAt >= 0, markerAt < ns.length else { return nil }
    guard ns.substring(to: markerAt)
        .trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
    guard value.isFinite else { return nil }
    // The user's `to|in <target>` suffix, verbatim.
    let suffix = ns.substring(from: markerAt + 1)
    guard suffix.trimmingCharacters(in: .whitespaces).contains(where: { $0.isLetter }) else {
        return nil
    }
    var literal = String(value)
    if context.decimalComma {
        literal = literal.replacingOccurrences(of: ".", with: ",")
    }
    // r92: a unit-bearing linked answer may REPEAT its own unit explicitly
    // (`4673 mg` + `<token> mg to kg`). Appending the carried label to a
    // suffix that already supplies a source unit would duplicate it
    // (`4673 mg mg to kg`) and surface the misleading `Unknown units`,
    // although both units are known. Probe the engine's OWN keyword
    // grammar for an explicit source and resolve the pair before
    // synthesizing.
    let trimmedSuffix = suffix.trimmingCharacters(in: .whitespaces)
    if let carriedUnit, !carriedUnit.isEmpty,
       let explicitSource = linkedExplicitSourceUnit(of: trimmedSuffix,
                                                     context: context) {
        switch linkedSourceUnitAgreement(explicitSource: explicitSource,
                                         carriedUnit: carriedUnit,
                                         unitContext: unitContext) {
        case .agrees:
            // The user's own text already names the source unit — use it
            // verbatim, with no carried label appended.
            return tryConversion(literal + " " + trimmedSuffix,
                                 rates: rates, decimalPlaces: decimalPlaces,
                                 context: context, unitContext: unitContext)
        case .differs:
            // Two KNOWN but different units: the documented conflict class.
            // The linked answer's own unit is never silently re-based.
            return .error(message: "Incompatible units")
        case .unknown:
            // Agreement cannot be established (unknown explicit unit, or a
            // carried label that no longer resolves, e.g. a deleted custom
            // unit): keep today's behavior and let `tryConversion` report
            // its existing verdict rather than inventing one here.
            break
        }
    }
    // r93: target-only `in` on an INCH-carrying answer (`3 in` +
    // `<token> in cm`). The `in` is the conversion KEYWORD, so the suffix
    // names no source unit and the branch above declines; appending the
    // carried label would synthesize the ambiguous `3 in in cm` that the
    // ordinary shape refuses. Rewrite exactly this ambiguity into the
    // documented `to` spelling and let `tryConversion` convert it — the
    // adapter still never computes a value itself.
    if let carriedUnit, !carriedUnit.isEmpty,
       let inchTarget = linkedInchTargetOnlyTarget(of: trimmedSuffix,
                                                   carriedUnit: carriedUnit,
                                                   unitContext: unitContext) {
        return tryConversion(literal + " " + carriedUnit + " to " + inchTarget,
                             rates: rates, decimalPlaces: decimalPlaces,
                             context: context, unitContext: unitContext)
    }
    var synthetic = literal
    if let carriedUnit, !carriedUnit.isEmpty {
        synthetic += " " + carriedUnit
    }
    synthetic += " " + trimmedSuffix
    return tryConversion(synthetic, rates: rates, decimalPlaces: decimalPlaces,
                         context: context, unitContext: unitContext)
}

/// r93: the target of a TARGET-ONLY `in` suffix on an INCH-carrying linked
/// answer, or nil when the suffix is not that one ambiguity.
///
/// An inch source makes `<token> in cm` genuinely ambiguous: the `in` here
/// is the conversion KEYWORD, but the bridge would also append the carried
/// `in` label, synthesizing `3 in in cm` — which the ordinary shape refuses
/// (two `in` words, no `to`), so the documented `<token> in <unit>`
/// spelling failed on an inch-carrying answer with a generic
/// `Invalid expression`.
///
/// All three conditions must hold, and nothing is inferred otherwise:
///  1. the carried label IS the built-in inch unit — exact `kind`,
///     `vector`, `family` and `toBase` identity, so no other carried unit
///     can ever take this path;
///  2. the suffix's first whitespace-delimited token is exactly `in`
///     (case-insensitive);
///  3. a non-empty target follows (any spaces/tabs are tolerated).
///
/// The caller then rewrites the ambiguity into the documented `to` spelling
/// and still lets `tryConversion` do the conversion — this adapter never
/// converts or calculates anything itself, so target shorthand, the error
/// classes, currency rates and precision stay identical to a typed line.
private func linkedInchTargetOnlyTarget(of trimmedSuffix: String,
                                        carriedUnit: String,
                                        unitContext: UnitContext) -> String? {
    // (2) The suffix must begin with `in` as its own word.
    guard let headEnd = trimmedSuffix.firstIndex(where: { $0.isWhitespace }),
          trimmedSuffix[trimmedSuffix.startIndex..<headEnd]
              .caseInsensitiveCompare("in") == .orderedSame else { return nil }
    // (3) A non-empty target must follow.
    let target = trimmedSuffix[headEnd...].trimmingCharacters(in: .whitespaces)
    guard !target.isEmpty else { return nil }
    // (1) The carried label must BE the inch unit.
    let carried = carriedUnit.trimmingCharacters(in: .whitespaces)
    guard !carried.isEmpty,
          let carriedExpr = unitExpr(byLabel: carried, context: unitContext),
          let inchExpr = unitExpr(byLabel: "in", context: .builtIns),
          carriedExpr.kind == inchExpr.kind,
          carriedExpr.vector == inchExpr.vector,
          carriedExpr.family == inchExpr.family,
          carriedExpr.toBase == inchExpr.toBase else { return nil }
    return target
}

/// r92: the source unit the user typed EXPLICITLY before the `to|in`
/// keyword, or nil when the suffix supplies none. The suffix is probed
/// through the engine's own grammar (`conversionShape`, which already
/// implements the documented keyword rules including the inch-vs-`in`
/// disambiguation) so this can never drift from `tryConversion`.
private func linkedExplicitSourceUnit(of trimmedSuffix: String,
                                      context: NumberFormatContext) -> String? {
    guard let shape = conversionShape("1 " + trimmedSuffix, context: context),
          let fromText = shape.fromText,
          !fromText.isEmpty else { return nil }
    return fromText
}

/// r92: how an explicitly typed source unit relates to the unit a linked
/// answer already carries.
private enum LinkedSourceUnitAgreement {
    /// Same unit — the linked answer converts normally.
    case agrees
    /// Both units are known and different — a conflict, never a silent
    /// reinterpretation of the linked answer's unit.
    case differs
    /// Agreement cannot be established (one side does not resolve).
    case unknown
}

/// r92: classifies an explicitly typed source unit against the carried
/// label. Agreement is EXACT unit identity: either the labels match
/// case-insensitively, or both resolve and their `kind`, `vector`,
/// `family` and `toBase` all match — the same test `convertValue` applies
/// for a same-unit conversion. Same-kind equality is deliberately NOT
/// enough: `C°` versus `F°` and `USD` versus `EUR` differ in `kind`, so
/// they classify as `.differs` and can never be silently re-based.
private func linkedSourceUnitAgreement(explicitSource: String,
                                       carriedUnit: String,
                                       unitContext: UnitContext)
    -> LinkedSourceUnitAgreement {
    let explicit = explicitSource.trimmingCharacters(in: .whitespaces)
    let carried = carriedUnit.trimmingCharacters(in: .whitespaces)
    guard !explicit.isEmpty, !carried.isEmpty else { return .unknown }
    if explicit.caseInsensitiveCompare(carried) == .orderedSame {
        return .agrees
    }
    guard let explicitExpr = unitContext.resolveExpression(explicit),
          let carriedExpr = unitExpr(byLabel: carried, context: unitContext) else {
        return .unknown
    }
    if explicitExpr.unit.kind == carriedExpr.kind,
       explicitExpr.unit.vector == carriedExpr.vector,
       explicitExpr.unit.family == carriedExpr.family,
       explicitExpr.unit.toBase == carriedExpr.toBase {
        return .agrees
    }
    return .differs
}
