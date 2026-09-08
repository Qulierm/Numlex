import Foundation

// MARK: - R84: pixel / PPI conversion
//
// The PPI lane owns the STRICT pixel phrases:
//
//     `1 cm in px at 326 ppi`   length -> pixels
//     `100 px at 326 ppi in cm` pixels -> length
//
// Pixels are NOT a physical length: `px` lives in its own family
// (vector zero), so `10 px + 1 m` is an error — px never pretends to
// be a length. The ONLY bridge between pixels and lengths is an
// explicit PPI factor on the line: 1 ppi = 1 pixel per inch
// (1 in = 0.0254 m exactly). The lane runs BEFORE the mixed-unit
// stage (whose strict shape would otherwise fail on the `at … ppi`
// tail) and owns the line it matches: a matched phrase that cannot
// convert is a visible error, never a word-strip fallback.

public enum PixelConversion {
    /// 1 inch in metres (exact by definition).
    public static let inchInMetres = 0.0254

    /// One matched PPI phrase: the pixel count (for ->length), the
    /// length quantity (for ->px), the target length unit (for ->px
    /// the target is `px` itself), and the PPI factor.
    public struct Match: Equatable, Sendable {
        public let ppi: Double
        /// Pixels side (`px at N ppi …` form).
        public let pixels: Double?
        /// Length side (`… in px at N ppi` form).
        public let length: Quantity?
        /// The length unit the length sits in (source for ->px, target
        /// for ->length).
        public let unit: UnitExpr
        public let pixelsSideFirst: Bool

        public init(ppi: Double, pixels: Double?, length: Quantity?,
                    unit: UnitExpr, pixelsSideFirst: Bool) {
            self.ppi = ppi
            self.pixels = pixels
            self.length = length
            self.unit = unit
            self.pixelsSideFirst = pixelsSideFirst
        }
    }

    /// The shape match (nil = the line is not a PPI phrase — every
    /// other lane decides). A matched phrase is OWNED: `convert`
    /// returns the result or the strict error.
    public static func match(_ line: String, context: NumberFormatContext,
                             unitContext: UnitContext,
                             env: TypedEnv = TypedEnv()) -> Match? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let tokens = MixedUnitScanner.tokenize(trimmed, context: context,
                                                     unitContext: unitContext,
                                                     env: env),
              tokens.count >= 6 else { return nil }

        func pxToken(_ i: Int) -> UnitExpr? {
            guard tokens.indices.contains(i),
                  case .unit(let u, range: _) = tokens[i],
                  u.family == .pixels else { return nil }
            return u
        }
        func atWord(_ i: Int) -> Bool {
            guard tokens.indices.contains(i),
                  case .word(let w, range: _) = tokens[i] else { return false }
            return w == "at"
        }
        func ppiWord(_ i: Int) -> Bool {
            guard tokens.indices.contains(i),
                  case .word(let w, range: _) = tokens[i] else { return false }
            return w == "ppi"
        }
        func targetWord(_ i: Int) -> Bool {
            guard tokens.indices.contains(i),
                  case .word(let w, range: _) = tokens[i] else { return false }
            return w == "in" || w == "as" || w == "to"
        }
        func numberAt(_ i: Int) -> Double? {
            guard tokens.indices.contains(i),
                  case .number(let v, range: _) = tokens[i] else { return nil }
            return v.isFinite ? v : nil
        }
        func lengthQty(_ i: Int) -> Quantity? {
            guard tokens.indices.contains(i) else { return nil }
            switch tokens[i] {
            case .quantity(let q, range: _):
                guard q.display.isLinear, q.display.vector.l == 1,
                      q.display.vector.m == 0, q.display.vector.t == 0,
                      q.display.vector.a == 0, q.display.vector.i == 0
                else { return nil }
                return q
            case .unit(let u, range: _):
                guard u.isLinear, u.vector.l == 1, u.vector.m == 0,
                      u.vector.t == 0, u.vector.a == 0, u.vector.i == 0
                else { return nil }
                return Quantity(value: 1, display: u)
            case .word(let w, range: _):
                // `… in in` — the scanner reads the SECOND `in` as the
                // keyword; the inch unit still owns it (the only length
                // unit named `in`).
                if w == "in", let u = unitContext.resolveExpression("in")?.unit,
                   u.isLinear, u.vector.l == 1, u.vector.m == 0,
                   u.vector.t == 0, u.vector.a == 0, u.vector.i == 0 {
                    return Quantity(value: 1, display: u)
                }
                return nil
            default:
                return nil
            }
        }

        // Shape A: `<len> (in|as|to) px at <n> ppi`
        if case .quantity(let q, range: _) = tokens[0],
           q.display.isLinear, q.display.vector.l == 1,
           q.display.vector.m == 0, q.display.vector.t == 0,
           q.display.vector.a == 0, q.display.vector.i == 0,
           tokens.count == 6,
           targetWord(1),
           let px = pxToken(2),
           atWord(3),
           let n = numberAt(4),
           ppiWord(5) {
            return Match(ppi: n, pixels: nil, length: q, unit: px,
                         pixelsSideFirst: false)
        }
        // Shape B: `<n> px at <n> ppi (in|as|to) <len>`
        if case .quantity(let q, range: _) = tokens[0],
           q.display.family == .pixels,
           tokens.count == 6,
           atWord(1),
           let n = numberAt(2),
           ppiWord(3),
           targetWord(4),
           let target = lengthQty(5) {
            _ = pxToken
            return Match(ppi: n, pixels: q.value, length: target,
                         unit: target.display, pixelsSideFirst: true)
        }
        return nil
    }

    /// The owned conversion: the phrase matched — this is the ONLY
    /// verdict (result or strict error).
    public static func convert(_ m: Match,
                               decimalPlaces: Int) -> LineResult {
        guard m.ppi.isFinite, m.ppi > 0 else {
            return .error(message: "Invalid ppi")
        }
        let dp = max(decimalPlaces, 10)
        if let length = m.length, m.pixels == nil {
            // length -> pixels: metres × ppi / inch.
            guard let metres = length.baseValue else {
                return .error(message: "Invalid expression")
            }
            let px = metres * m.ppi / inchInMetres
            guard px.isFinite else { return .error(message: "Invalid ppi") }
            return .number(value: roundResult(px, decimalPlaces: dp), unit: "px")
        }
        if let px = m.pixels {
            // pixels -> length: px × inch / ppi, in the target unit.
            let metres = Double(px) * inchInMetres / m.ppi
            guard metres.isFinite, m.unit.toBase > 0, m.unit.isLinear else {
                return .error(message: "Incompatible units")
            }
            let v = metres / m.unit.toBase
            guard v.isFinite else { return .error(message: "Invalid ppi") }
            return .number(value: roundResult(v, decimalPlaces: dp),
                           unit: m.unit.label)
        }
        return .error(message: "Invalid expression")
    }

    /// Convenience entry: match + convert (nil when the line is not a
    /// PPI phrase).
    public static func tryConvert(_ line: String, context: NumberFormatContext,
                                  unitContext: UnitContext,
                                  decimalPlaces: Int,
                                  env: TypedEnv = TypedEnv()) -> LineResult? {
        guard let m = match(line, context: context, unitContext: unitContext,
                            env: env) else { return nil }
        return convert(m, decimalPlaces: decimalPlaces)
    }
}
