import Foundation

// MARK: - R84: quantity algebra model
//
// A real quantity is NOT its display label. It carries a finite value
// in a declared display unit's scale plus a bounded identity that the
// display String only ever PRESENTS:
//   - a `DimensionSignature` (the five SI base exponents plus bounded
//     custom-dimension exponents),
//   - a `UnitFamily` wall (energy vs torque, angle vs data, ...),
//   - a `UnitKind` conversion class (linear / temperature / currency /
//     fuel),
//   - the display unit itself (a `UnitExpr`: scale factor to base,
//     canonical label, normalized name).
//
// `Quantity` is immutable and value-semantics. All algebra is strict:
// incompatible operands are an error, never a silent fallback, and
// every operation guards finiteness and bounded exponents. The
// persisted Sheet / `.nlx` schema is untouched — quantities are
// re-derived from sheet text on every evaluation pass.

/// A bounded dimension signature: the five physical base dimensions
/// (a `DimensionVector`) plus exponents over DYNAMIC custom dimensions.
///
/// Built-in quantities leave `custom` empty, so a built-in signature is
/// exactly its `DimensionVector` — every pre-R84 identity check
/// (vector + family) is preserved byte-for-byte. A custom unit that
/// declares an independent dimension gets a unique axis here; its
/// exponent is bounded the same way the base exponents are.
public struct DimensionSignature: Hashable, Sendable, Equatable {
    /// The five physical base dimensions (L M T A I).
    public var base: DimensionVector
    /// Exponents over custom (user-defined) independent dimensions,
    /// keyed by the stable ordinal assigned to each such unit. Empty for
    /// every built-in quantity.
    public var custom: [Int: Int8]

    public init(base: DimensionVector = .zero, custom: [Int: Int8] = [:]) {
        self.base = base
        // Drop zero exponents so the dictionary stays minimal/hash-stable.
        self.custom = custom.filter { $0.value != 0 }
    }

    /// The dimensionless signature.
    public static let zero = DimensionSignature()

    public var isDimensionless: Bool {
        base.isDimensionless && custom.isEmpty
    }

    /// Multiplication of signatures (exponents add). Bounded: an exponent
    /// that would overflow Int8 collapses the signature to `nil` so a
    /// runaway compound can never silently wrap.
    public static func * (lhs: DimensionSignature, rhs: DimensionSignature) -> DimensionSignature? {
        guard let b = combine(lhs.base, rhs.base, divide: false),
              let c = merge(lhs.custom, rhs.custom, divide: false) else { return nil }
        return DimensionSignature(base: b, custom: c)
    }

    /// Division of signatures (exponents subtract), bounded as `*`.
    public static func / (lhs: DimensionSignature, rhs: DimensionSignature) -> DimensionSignature? {
        guard let b = combine(lhs.base, rhs.base, divide: true),
              let c = merge(lhs.custom, rhs.custom, divide: true) else { return nil }
        return DimensionSignature(base: b, custom: c)
    }

    /// Bounded integer power (0...3, mirroring `DimensionVector.powered`).
    public func powered(_ n: Int) -> DimensionSignature? {
        guard n >= 0, n <= 3 else { return nil }
        let e = Int(n)
        func scale(_ x: Int8) -> Int8? {
            let v = Int(x) * e
            guard v >= Int8.min, v <= Int8.max else { return nil }
            return Int8(v)
        }
        guard let l = scale(base.l), let m = scale(base.m),
              let t = scale(base.t), let a = scale(base.a),
              let i = scale(base.i) else { return nil }
        var c: [Int: Int8] = [:]
        for (k, x) in custom {
            guard let s = scale(x) else { return nil }
            if s != 0 { c[k] = s }
        }
        return DimensionSignature(base: DimensionVector(l: l, m: m, t: t, a: a, i: i), custom: c)
    }

    // Combine two base vectors, adding (multiply) or subtracting (divide)
    // each axis in bounded Int range; nil on any overflow.
    private static func combine(_ a: DimensionVector, _ b: DimensionVector,
                                divide: Bool) -> DimensionVector? {
        func op(_ x: Int8, _ y: Int8) -> Int8? {
            let v = Int(x) + (divide ? -Int(y) : Int(y))
            guard v >= Int8.min, v <= Int8.max else { return nil }
            return Int8(v)
        }
        guard let l = op(a.l, b.l), let m = op(a.m, b.m),
              let t = op(a.t, b.t), let a2 = op(a.a, b.a),
              let i = op(a.i, b.i) else { return nil }
        return DimensionVector(l: l, m: m, t: t, a: a2, i: i)
    }

    // Merge two custom exponent maps, adding or subtracting per axis and
    // dropping axes that cancel to zero; nil on any overflow.
    private static func merge(_ l: [Int: Int8], _ r: [Int: Int8],
                              divide: Bool) -> [Int: Int8]? {
        var out = l
        for (k, e) in r {
            let cur = Int(out[k] ?? 0) + (divide ? -Int(e) : Int(e))
            guard cur >= Int8.min, cur <= Int8.max else { return nil }
            if cur == 0 { out[k] = nil } else { out[k] = Int8(cur) }
        }
        return out
    }
}

// MARK: - Quantity

/// One finite quantity: a value in the scale of `display` plus its
/// bounded identity. This is the R84 currency of the mixed-unit engine,
/// the custom-unit resolver, the generalized rate/pace/transfer grammars
/// and the quantity Answer Tokens.
public struct Quantity: Equatable, Sendable {
    /// The value in the scale of `display` (native scale for the
    /// special kinds: kelvin for temperature, the currency code for
    /// currency, L/m for fuel).
    public var value: Double
    /// The display unit (scale + label + identity).
    public var display: UnitExpr

    public init(value: Double, display: UnitExpr) {
        self.value = value
        self.display = display
    }

    // Identity projections (cached off `display`).
    public var kind: UnitKind { display.kind }
    public var vector: DimensionVector { display.vector }
    public var family: UnitFamily { display.family }
    /// The full signature: the linear vector (custom units contribute
    /// their dynamic axis) — `display.signature` when present.
    public var signature: DimensionSignature { display.quantitySignature }
    public var isLinear: Bool { display.isLinear }
    public var isSpecial: Bool { display.isSpecial }

    /// The unitless (dimensionless, plain) quantity — the identity for
    /// additive assimilation and the result of a full cancellation.
    public static let unitless = Quantity(
        value: 0,
        display: UnitExpr(kind: .factor(.zero, 1), vector: .zero, family: .none,
                          toBase: 1, label: "", name: "1"))

    /// A unitless quantity with a value (a plain number riding the
    /// algebra so `300 + 20 km` can assimilate the 300).
    public static func plain(_ value: Double) -> Quantity {
        Quantity(value: value, display: unitless.display)
    }

    public var isPlain: Bool {
        isLinear && signature == .zero && family == .none
    }

    /// The value in BASE units (linear only; the special kinds have no
    /// shared linear base and return nil).
    public var baseValue: Double? {
        guard isLinear, value.isFinite, display.toBase.isFinite, display.toBase > 0
        else { return nil }
        let v = value * display.toBase
        return v.isFinite ? v : nil
    }

    // MARK: Additive / subtractive algebra

    /// Add (or subtract) two quantities. Strict rules:
    /// - both special, or a special mixed with anything: reject (an
    ///   affine/finite transform has no algebra);
    /// - both linear: signatures (vector + family + custom) must match;
    /// - exactly one side unitless: assimilate it to the other side's
    ///   unit (`300 + 20 km` = 320 km) — the unitless side converts to
    ///   the other's BASE and back into the chosen display unit;
    /// - otherwise: the result takes the COARSER (larger toBase factor)
    ///   display unit regardless of operand order; an equal factor keeps
    ///   the LEFT (stable) operand's unit.
    public func added(_ other: Quantity, negative: Bool = false) -> Result<Quantity, QuantityError> {
        guard value.isFinite, other.value.isFinite else { return .failure(.nonFinite) }
        if !isLinear || !other.isLinear {
            return .failure(.incompatible("additive"))
        }
        let aSig = signature, bSig = other.signature
        let aPlain = isPlain, bPlain = other.isPlain
        // Compatibility: identical signatures, OR one side plain.
        if aSig != bSig {
            guard aPlain || bPlain else { return .failure(.incompatible("additive")) }
        }
        // Choose the display unit.
        let (target, aBase, bBase): (UnitExpr, Double?, Double?)
        if aPlain && bPlain {
            // Plain + plain: plain result.
            let v = negative ? value - other.value : value + other.value
            guard v.isFinite else { return .failure(.nonFinite) }
            return .success(.plain(v))
        } else if aPlain {
            // Assimilate a into b's unit: the PLAIN side counts in the
            // other side's display unit (`300 + 20 km` = 320 km).
            target = other.display
            let v = negative ? other.value - value : other.value + value
            guard v.isFinite else { return .failure(.nonFinite) }
            return .success(Quantity(value: v, display: target))
        } else if bPlain {
            target = display
            let v = negative ? value - other.value : value + other.value
            guard v.isFinite else { return .failure(.nonFinite) }
            return .success(Quantity(value: v, display: target))
        } else {
            // Both dimensional: signatures must match (checked above).
            guard let av = baseValue, let bv = other.baseValue else {
                return .failure(.nonFinite)
            }
            aBase = av; bBase = bv
            // Coarser (larger toBase factor) wins; equal -> LEFT unit.
            let af = display.toBase, bf = other.display.toBase
            target = (bf > af) ? other.display : display
        }
        guard let ab = aBase, let bb = bBase else { return .failure(.nonFinite) }
        let baseSum = negative ? ab - bb : ab + bb
        guard baseSum.isFinite else { return .failure(.nonFinite) }
        // Convert the summed base value into the target unit's scale.
        let outValue: Double
        if target.isLinear, target.toBase > 0 {
            outValue = baseSum / target.toBase
        } else {
            outValue = baseSum
        }
        guard outValue.isFinite else { return .failure(.nonFinite) }
        return .success(Quantity(value: outValue, display: target))
    }

    public func subtracted(_ other: Quantity) -> Result<Quantity, QuantityError> {
        added(other, negative: true)
    }

    // MARK: Multiplicative / divisive algebra

    /// Multiply (or divide) two quantities. Strict rules:
    /// - any special operand: reject (no algebra with affine/currency/
    ///   fuel quantities);
    /// - dimensions combine (multiply) or cancel (divide); a result that
    ///   returns to the dimensionless zero signature AND `.none` family
    ///   is a PLAIN scalar (the unit falls away);
    /// - a result matching a known catalog unit in BOTH vector and family
    ///   canonicalizes to that unit; otherwise it keeps a deterministic
    ///   pretty compound label;
    /// - exponent overflow or a non-finite factor is an error.
    public func multiplied(_ other: Quantity, divide: Bool = false) -> Result<Quantity, QuantityError> {
        guard value.isFinite, other.value.isFinite else { return .failure(.nonFinite) }
        if !isLinear || !other.isLinear { return .failure(.incompatible("multiplicative")) }
        // A plain scalar scales the other side IN PLACE: `50% of 100
        // km` = 20 km (never 20000 m), `7 day / 2` = 3.5 day.
        if isPlain && !other.isPlain {
            let v = divide ? (other.value / value) : (other.value * value)
            guard v.isFinite else { return .failure(.nonFinite) }
            if !divide {
                return .success(Quantity(value: v, display: other.display))
            }
            // plain / dimensional: the inverse-unit rate `1/<unit>`.
            guard value != 0 else { return .failure(.divisionByZero) }
            let f = other.display.toBase
            guard f > 0, f.isFinite else { return .failure(.nonFinite) }
            let inv = DimensionSignature.zero / other.signature
            guard let inv = inv else { return .failure(.exponentOverflow) }
            let label = "1/" + other.display.label
            let expr = UnitExpr(kind: .factor(inv.base, f), vector: inv.base,
                                family: .none, toBase: f, label: label, name: label)
            return .success(Quantity(value: v, display: expr))
        }
        if other.isPlain && !isPlain {
            let v = divide ? (value / other.value) : (value * other.value)
            guard v.isFinite else { return .failure(.nonFinite) }
            if divide, other.value == 0 { return .failure(.divisionByZero) }
            return .success(Quantity(value: v, display: display))
        }
        let sig = divide ? (signature / other.signature) : (signature * other.signature)
        guard let s = sig else { return .failure(.exponentOverflow) }
        let aF = display.toBase, bF = other.display.toBase
        guard aF > 0, bF > 0, aF.isFinite, bF.isFinite else { return .failure(.nonFinite) }
        let factor = divide ? (aF / bF) : (aF * bF)
        guard factor.isFinite, factor > 0 else { return .failure(.nonFinite) }
        let value2 = divide ? (value / other.value) : (value * other.value)
        guard value2.isFinite else { return .failure(.nonFinite) }
        // Family: the numerator (left) family wins; a dimensionless
        // result with `.none` family becomes a plain scalar.
        let family = divide ? family : (family == .none ? other.family : family)
        let outFamily = (s == .zero) ? .none : family
        if s == .zero && outFamily == .none {
            return .success(.plain(value2))
        }
        // Label preservation for products:
        //  - equal labels: `10 m × 10 m` keeps `m²` (not the base `m²`
        //    re-derived as `10000 m²`-style base); `10 km × 10 km` → km².
        if !divide, display.label == other.display.label,
           display.vector == other.vector,
           display.label != "", display.label != "1" {
            let exp = s.base.l + s.base.m + s.base.t + s.base.a + s.base.i
            guard exp == 2 || exp == 3 else {
                return .failure(.exponentOverflow)
            }
            let label = exp == 2 ? display.label + "²" : display.label + "³"
            let expr = UnitExpr(kind: .factor(s.base, aF * bF), vector: s.base,
                                family: outFamily, toBase: aF * bF,
                                label: label, name: label)
            return .success(Quantity(value: value2, display: expr))
        }
        //  - rate × its denominator: `30 km/day × 2 day` = `60 km`
        //    (the distance label survives the time cancellation).
        if !divide {
            if let (num, den) = Quantity.splitRateLabel(display),
               Quantity.denVectorMatches(other.vector, of: den) {
                return Quantity.rateSurvivor(value: value2, keep: num,
                                             s: s, family: outFamily)
            }
            if let (num, den) = Quantity.splitRateLabel(other.display),
               Quantity.denVectorMatches(display.vector, of: den) {
                return Quantity.rateSurvivor(value: value2, keep: num,
                                             s: s, family: outFamily)
            }
        }
        // Canonicalize to a known unit when vector AND family match.
        if let known = Self.canonicalUnit(vector: s.base, family: outFamily) {
            // Convert the combined factor into the known unit's scale.
            guard let toKnown = known.linearFactor, toKnown > 0, toKnown.isFinite
            else { return .failure(.nonFinite) }
            let baseVal = value2 * factor          // in base units
            let outValue = baseVal / toKnown
            guard outValue.isFinite else { return .failure(.nonFinite) }
            let knownExpr = UnitExpr(kind: .factor(s.base, toKnown), vector: s.base,
                                     family: outFamily, toBase: toKnown,
                                     label: known.label, name: known.label)
            return .success(Quantity(value: outValue, display: knownExpr))
        }
        // Otherwise: a derived compound unit with a pretty label.
        let label = Self.prettyDerived(vector: s.base, factor: factor)
        let expr = UnitExpr(kind: .factor(s.base, factor), vector: s.base,
                            family: outFamily, toBase: factor,
                            label: label, name: label)
        return .success(Quantity(value: value2, display: expr))
    }

    public func divided(_ other: Quantity) -> Result<Quantity, QuantityError> {
        guard other.value != 0 else { return .failure(.divisionByZero) }
        guard value.isFinite, other.value.isFinite else { return .failure(.nonFinite) }
        if !isLinear || !other.isLinear {
            return .failure(.incompatible("multiplicative"))
        }
        let aPlain = isPlain, bPlain = other.isPlain
        // Cancellation: identical signatures divide to a scalar —
        // EXCEPT a bare-unit divisor keeps its rate reading (`3 hours
        // / day` stays the `h/day` rate at value 3).
        if !aPlain, !bPlain, signature == other.signature {
            if bPlain == false, other.value == 1 {
                let label = display.label + "/" + other.display.label
                let f = display.toBase / other.display.toBase
                guard f > 0, f.isFinite else { return .failure(.nonFinite) }
                let sig = signature
                let expr = UnitExpr(kind: .factor(sig.base, f), vector: sig.base,
                                    family: .none, toBase: f, label: label, name: label)
                return .success(Quantity(value: value, display: expr))
            }
            guard let av = baseValue, let bv = other.baseValue else {
                return .failure(.nonFinite)
            }
            let v = av / bv
            guard v.isFinite else { return .failure(.nonFinite) }
            return .success(.plain(v))
        }
        // A rate result keeps the OPERAND labels: `90 km / 3 day`
        // displays `km/day`, `2.5 kg / 5 L` displays `kg/L`.
        if !aPlain, !bPlain {
            let sig = signature / other.signature
            guard let s = sig else { return .failure(.exponentOverflow) }
            let f = display.toBase / other.display.toBase
            guard f > 0, f.isFinite else { return .failure(.nonFinite) }
            let label = display.label + "/" + other.display.label
            let expr = UnitExpr(kind: .factor(s.base, f), vector: s.base,
                                family: .none, toBase: f, label: label, name: label)
            let v = value / other.value
            guard v.isFinite else { return .failure(.nonFinite) }
            return .success(Quantity(value: v, display: expr))
        }
        return multiplied(other, divide: true)
    }

    /// Bounded integer power (2 or 3) of a LINEAR quantity. A plain
    /// quantity powers to a plain quantity; a dimensional quantity
    /// powers its vector/factor with a `label²`/`label³` presentation.
    public func powered(_ n: Int) -> Result<Quantity, QuantityError> {
        guard n == 2 || n == 3 else { return .failure(.exponentOverflow) }
        guard value.isFinite else { return .failure(.nonFinite) }
        if !isLinear { return .failure(.incompatible("power")) }
        guard let sig = signature.powered(n) else { return .failure(.exponentOverflow) }
        let f = pow(display.toBase, Double(n))
        guard f.isFinite, f > 0 else { return .failure(.nonFinite) }
        let v = pow(value, Double(n))
        guard v.isFinite else { return .failure(.nonFinite) }
        if isPlain { return .success(.plain(v)) }
        let label = n == 2 ? display.label + "²" : display.label + "³"
        let expr = UnitExpr(kind: .factor(sig.base, f), vector: sig.base,
                            family: family, toBase: f, label: label, name: label)
        return .success(Quantity(value: v, display: expr))
    }

    // MARK: Rate label helpers

    /// Splits a two-part rate label (`km/day`) into (numerator,
    /// denominator) unit labels; nil when the display is not a
    /// `<unit>/<unit>` rate.
    static func splitRateLabel(_ e: UnitExpr) -> (String, String)? {
        let label = e.label
        guard let slash = label.firstIndex(of: "/"), label != "" else { return nil }
        let num = String(label[..<slash])
        let den = String(label[label.index(after: slash)...])
        guard !num.isEmpty, !den.isEmpty else { return nil }
        return (num, den)
    }

    /// Whether `vec` equals the vector of the unit named `label`.
    static func denVectorMatches(_ vec: DimensionVector, of label: String) -> Bool {
        guard let u = UnitCatalog.resolveLabel(label) ??
            UnitCatalog.resolveExpression(label)?.unit else { return false }
        return u.vector == vec && u.vector != .zero
    }

    /// The survivor of a rate × complementary-unit product: the kept
    /// label rides its OWN catalog scale (the product value is
    /// already in that unit's display scale: `30 km/day × 2 day` =
    /// `60 km`).
    static func rateSurvivor(value: Double, keep: String,
                             s: DimensionSignature, family: UnitFamily)
        -> Result<Quantity, QuantityError> {
        guard value.isFinite else { return .failure(.nonFinite) }
        guard let twin = UnitCatalog.resolveLabel(keep) ??
            UnitCatalog.resolveExpression(keep)?.unit,
            twin.isLinear, twin.toBase > 0 else {
            return .failure(.incompatible("rate survivor"))
        }
        let expr = UnitExpr(kind: .factor(s.base, twin.toBase), vector: s.base,
                            family: family, toBase: twin.toBase,
                            label: twin.label, name: twin.label)
        return .success(Quantity(value: value, display: expr))
    }

    // MARK: Conversion

    /// Convert this quantity into `target` using the shared `convertValue`
    /// engine (linear, temperature, currency-with-rates, fuel). Returns
    /// the converted value riding the target's display. Fails when the
    /// pair is unsupported.
    public func converted(to target: UnitExpr, rates: Rates) -> Result<Quantity, QuantityError> {
        guard value.isFinite else { return .failure(.nonFinite) }
        // Two LINEAR units with the SAME vector convert by the plain
        // base-factor ratio — this covers rate/area/compound displays
        // the built-in engine only knows in their catalog forms.
        if isLinear, target.isLinear, display.vector == target.vector,
           display.family == target.family,
           display.toBase > 0, target.toBase > 0 {
            let v = value * display.toBase / target.toBase
            guard v.isFinite else { return .failure(.nonFinite) }
            return .success(Quantity(value: v, display: target))
        }
        // Cross-kind (fuel economy, currency, temperature): the shared
        // engine only understands CATALOG forms — canonicalize the
        // display into its catalog twin before delegating.
        var from = display
        var v = value
        if let twin = Self.canonicalUnit(vector: display.vector, family: display.family) {
            guard let f = twin.linearFactor, f > 0, f.isFinite else { return .failure(.nonFinite) }
            let baseVal = value * display.toBase
            let twinValue = baseVal / f
            guard twinValue.isFinite else { return .failure(.nonFinite) }
            from = UnitExpr(kind: .factor(display.vector, f), vector: display.vector,
                            family: display.family, toBase: f,
                            label: twin.label, name: twin.label)
            v = twinValue
        }
        if let r = convertValue(v, from: from, to: target, rates: rates),
           r.value.isFinite {
            return .success(Quantity(value: r.value, display: target))
        }
        // Fuel-economy bridge: a custom per-liter result (vector L⁻²,
        // e.g. `1 km / L`) converts through the catalog's km/L anchor
        // into the fuel family (`1 km / L to L / 100km` = 10).
        if target.isLinear == false,
           display.vector.l == -2, display.vector.m == 0,
           display.vector.t == 0, display.vector.a == 0, display.vector.i == 0,
           let anchor = Self.fuelAnchorExpr(),
           let anchorBase = Self.fuelAnchorBase() {
            // Re-express the per-liter value in the anchor's scale:
            // 1 km/L ≡ 1000 m per 0.001 m³ ≡ 1e6 in the base m⁻².
            let kmLValue = value * display.toBase / anchorBase
            guard kmLValue.isFinite, kmLValue > 0 else {
                return .failure(.incompatible("conversion"))
            }
            if let r = convertValue(kmLValue, from: anchor, to: target, rates: rates),
               r.value.isFinite {
                return .success(Quantity(value: r.value, display: target))
            }
        }
        return .failure(.incompatible("conversion"))
    }

    /// The catalog's km/L fuel unit as a `UnitExpr` (the anchor of the
    /// fuel-economy family).
    static func fuelAnchorExpr() -> UnitExpr? {
        guard let pe = UnitCatalog.resolveExpression("km/L"),
              pe.unit.isLinear == false else { return nil }
        return pe.unit
    }

    /// The anchor scale in base m⁻²: (km in m) / (litre in m³).
    static func fuelAnchorBase() -> Double? {
        guard let km = UnitCatalog.resolveExpression("km"),
              let l = UnitCatalog.resolveExpression("L"),
              km.unit.isLinear, l.unit.isLinear,
              km.unit.toBase > 0, l.unit.toBase > 0 else { return nil }
        let b = km.unit.toBase / l.unit.toBase
        return b.isFinite ? b : nil
    }

    // MARK: Canonicalization helpers

    /// The built-in catalog unit whose vector AND family match exactly
    /// (used to canonicalize a derived result back to a known unit).
    static func canonicalUnit(vector: DimensionVector, family: UnitFamily) -> UnitDef? {
        for u in UnitCatalog.all {
            guard let v = u.vector, v == vector else { continue }
            guard u.family == family else { continue }
            if let f = u.linearFactor, f > 0, f.isFinite { return u }
        }
        return nil
    }
    /// A deterministic pretty label for a derived compound unit that has
    /// no single catalog owner (e.g. `km/day`, `m²`, `$ / kg`).
    static func prettyDerived(vector: DimensionVector, factor: Double) -> String {
        // Build a label from the vector's base dimensions, falling back
        // to a stable "derived" tag when the vector is unusual.
        var parts: [String] = []
        func push(_ dim: Character, _ e: Int8) {
            guard e != 0 else { return }
            let core = e == 1 ? String(dim) : "\(dim)^\(e)"
            parts.append(core)
        }
        push("L", vector.l); push("M", vector.m); push("T", vector.t)
        push("A", vector.a); push("I", vector.i)
        if parts.isEmpty { return "unit" }
        return parts.joined(separator: "·")
    }
}

// MARK: - Errors

/// The strict failure vocabulary of the quantity algebra. Every case is
/// surfaced as the generic hidden error by the caller (the message is
/// metadata for tests/diagnostics, never shown verbatim to the user).
public enum QuantityError: Equatable, Sendable, Error {
    case nonFinite
    case incompatible(String)
    case exponentOverflow
    case divisionByZero
    case unsupported
}

// MARK: - UnitExpr extension: quantity signature

extension UnitExpr {
    /// True for the finite-transform kinds (temperature/currency/fuel).
    public var isSpecial: Bool { !isLinear }

    /// The full dimension signature of this unit. Built-in units carry
    /// exactly their `vector` (empty custom axes); custom units that
    /// declare an independent dimension carry that axis here.
    public var quantitySignature: DimensionSignature {
        if let axis = customAxis {
            return DimensionSignature(base: .zero, custom: [axis: 1])
        }
        return DimensionSignature(base: vector)
    }

    /// The stable ordinal of the custom independent dimension this unit
    /// declares (nil for every built-in and for custom units that are
    /// defined against existing dimensions).
    public var customAxis: Int? {
        // A custom new-dimension unit is tagged through its `name`.
        if name.hasPrefix("r84custom") {
            let suffix = name.dropFirst("r84custom".count)
            if let n = Int(suffix), n >= 0 { return n }
        }
        return nil
    }
}
