import Foundation

// MARK: - R84: rate / pace / transfer / price-per-unit phrases
//
// Two strict phrase lanes on top of the quantity algebra:
//
//   1. THE RATE PHRASE — `<qtyA> in <qtyB>`:
//      `10 km in 45 min`  -> 0.2222 km/min   (speed)
//      `45 min in 10 km`  -> 4.5 min/km      (pace)
//      `1 Gbit in 5 s`    -> 0.2 Gbit/s      (transfer rate)
//   It is A over B through the shared `divided` algebra (the operand
//   labels carry the rate: `km/min`, `min/km`, `Gbit/s`). Only the
//   `in` spelling is a phrase here — `per` is a mixed-stage operator
//   (`90 km per 3 day` parses in the unit algebra itself), and
//   `<len> in <unit>` WITHOUT a number on the right stays a plain
//   unit conversion (`10 km in m`).
//
//   2. THE PRICE-PER-UNIT PHRASE — `<qty> at <money> per <unit>`:
//      `2.5 kg at €3 per kg` -> €7.50
//      `200 g at $7.50 per kg` -> $3.00
//   The money operand is a symbol-led or code-led amount; the result
//   is a pure MONEY answer in that code (qty/unit × price).
//
// Both lanes run BEFORE the mixed-unit stage (the mixed shape cannot
// see the `in` phrase, and money symbols stop the mixed scanner) and
// own the line they match: a matched phrase that fails is a visible
// error, never a word-strip fallback.
public enum RatePhrases {
    /// The rate phrase `<qtyA> in <qtyB>`.
    public static func tryRatePhrase(_ line: String,
                                     context: NumberFormatContext,
                                     unitContext: UnitContext,
                                     decimalPlaces: Int,
                                     env: TypedEnv = TypedEnv()) -> LineResult? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let tokens = MixedUnitScanner.tokenize(trimmed, context: context,
                                                     unitContext: unitContext,
                                                     env: env),
              tokens.count == 3 else { return nil }
        guard case .quantity(let a, range: _) = tokens[0],
              case .word(let w, range: _) = tokens[1], w == "in",
              case .quantity(let b, range: _) = tokens[2]
        else { return nil }
        guard a.display.isLinear, b.display.isLinear else { return nil }
        guard let q = tryDivided(a, b) else {
            return .error(message: "Incompatible units")
        }
        return .number(value: roundResult(q.value,
                                          decimalPlaces: max(decimalPlaces, 10)),
                       unit: q.display.label, kind: .plain, fraction: nil)
    }

    private static func tryDivided(_ a: Quantity, _ b: Quantity) -> Quantity? {
        guard case .success(let r) = a.divided(b) else { return nil }
        return r
    }

    // MARK: Price-per-unit phrase

    /// One matched price phrase.
    public struct PriceMatch: Equatable, Sendable {
        public let qty: Quantity
        public let price: Double
        public let code: String
        public let unit: UnitExpr
        public init(qty: Quantity, price: Double, code: String, unit: UnitExpr) {
            self.qty = qty
            self.price = price
            self.code = code
            self.unit = unit
        }
    }

    /// The shape match of `<qty> at <money> per <unit>` (nil = some
    /// other lane decides).
    public static func matchPrice(_ line: String, context: NumberFormatContext,
                                  unitContext: UnitContext) -> PriceMatch? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // ` at ` is the exact separator (spaced both sides).
        guard let atRange = trimmed.range(of: " at ") else { return nil }
        let left = String(trimmed[..<atRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        let right = String(trimmed[atRange.upperBound...]).trimmingCharacters(in: .whitespaces)

        // Left: `<number> <unit expression>`
        guard let space = left.firstIndex(of: " "), space != left.startIndex
        else { return nil }
        let numText = String(left[..<space])
        let unitText = String(left[left.index(after: space)...])
        guard !unitText.isEmpty,
              let num = parseAmount(numText, context: context), num.isFinite,
              let u = unitContext.resolveExpression(unitText)?.unit,
              u.isLinear, !u.isSpecial
        else { return nil }
        let qty = Quantity(value: num, display: u)

        // Right: `<money> per <unit expression>`
        guard let perRange = right.range(of: " per ") else { return nil }
        let moneyText = String(right[..<perRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        let unitRight = String(right[perRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !unitRight.isEmpty,
              let (price, code) = parseMoney(moneyText), price.isFinite
        else { return nil }
        guard let tu = unitContext.resolveExpression(unitRight)?.unit,
              tu.isLinear, !tu.isSpecial
        else { return nil }
        return PriceMatch(qty: qty, price: price, code: code, unit: tu)
    }

    /// The owned price conversion: qty/unit × price, in the money's
    /// code.
    public static func convertPrice(_ m: PriceMatch,
                                    decimalPlaces: Int) -> LineResult {
        guard m.qty.display.vector == m.unit.vector,
              m.qty.display.isLinear, m.unit.isLinear,
              m.unit.toBase > 0, m.qty.display.toBase > 0
        else { return .error(message: "Incompatible units") }
        let inUnit = m.qty.value * m.qty.display.toBase / m.unit.toBase
        let total = inUnit * m.price
        guard total.isFinite else { return .error(message: "Invalid expression") }
        return .money(value: total, code: m.code)
    }

    /// Convenience entry: match + convert (nil when the line is not a
    /// price phrase).
    public static func tryPricePhrase(_ line: String,
                                      context: NumberFormatContext,
                                      unitContext: UnitContext,
                                      decimalPlaces: Int) -> LineResult? {
        guard let m = matchPrice(line, context: context, unitContext: unitContext)
        else { return nil }
        return convertPrice(m, decimalPlaces: decimalPlaces)
    }

    // MARK: Number parsing (context-aware)

    /// A decimal amount with the context's separators: grouping
    /// stripped, a decimal comma becomes a dot.
    static func parseAmount(_ text: String,
                            context: NumberFormatContext = .legacy) -> Double? {
        let hasComma = text.contains(",")
        let hasDot = text.contains(".")
        guard !(hasComma && hasDot) else { return nil }
        var t = text
        if hasComma {
            t = t.replacingOccurrences(of: ",", with: "")
        } else if hasDot {
            t = t.replacingOccurrences(of: ".", with: ".")
        }
        guard let v = Double(t) else { return nil }
        return v
    }

    /// Currency amount: digits with grouping commas and/or a decimal
    /// dot (money keeps US-style grouping regardless of the input
    /// context: `€1,234.50`).
    static func parseCurrencyAmount(_ text: String) -> Double? {
        var t = text
        if t.contains(",") && t.contains(".") {
            t = t.replacingOccurrences(of: ",", with: "")
        } else if t.contains(",") {
            // A lone comma: decimal or grouping — prefer grouping for
            // 3-digit tails (`1,234`), decimal otherwise (`12,5`).
            let tail = t.components(separatedBy: ",").last ?? ""
            t = (tail.count == 3) ? t.replacingOccurrences(of: ",", with: "")
                : t.replacingOccurrences(of: ",", with: ".")
        }
        guard let v = Double(t) else { return nil }
        return v
    }

    /// A symbol-led (`€3`, `$1,234.50`) or code-led (`EUR 3`) amount.
    static func parseMoney(_ text: String) -> (value: Double, code: String)? {
        // Symbol-led: the longest marker first.
        for marker in CurrencyPresentation.orderedMarkers {
            if text.hasPrefix(marker), marker != text {
                let rest = String(text.dropFirst(marker.count))
                let parts = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
                if let first = parts.first, let v = parseCurrencyAmount(String(first)) {
                    guard let code = CurrencyPresentation.code(forMarker: marker)
                    else { return nil }
                    return (v, code)
                }
            }
        }
        // Code-led: `EUR 3.5` (uppercase ISO code, then a space).
        if let space = text.firstIndex(of: " ") {
            let code = String(text[..<space]).uppercased()
            if code.count == 3, code.allSatisfy({ $0.isASCII && $0.isLetter }) {
                let rest = String(text[text.index(after: space)...])
                if let v = parseCurrencyAmount(rest), UnitCatalog.resolveExpression(code) != nil {
                    return (v, code)
                }
            }
        }
        return nil
    }
}
