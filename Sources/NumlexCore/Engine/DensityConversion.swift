import Foundation

// MARK: - R84: cooking density conversions
//
// The density lane owns the STRICT cooking phrases:
//
//     `200 g of flour to ml`     mass -> volume
//     `1 cup of honey to g`      volume -> mass
//     `1 L of oil as kg`         (in|as|to targets)
//
// The operand is a mass OR a volume quantity, `of <ingredient>`
// names the (approximate) pack density from the versioned
// `CookingDensities` table, and the target is the opposite kind.
// The lane runs BEFORE the mixed-unit stage (whose `of` = multiply
// reading would fail on the ingredient word) and owns the line it
// matches: an unknown ingredient or a kind-mismatched target is a
// visible error, never a word-strip fallback.

public enum DensityConversion {
    /// One matched density phrase.
    public struct Match: Equatable, Sendable {
        public let operand: Quantity
        public let ingredient: String
        public let target: UnitExpr
        public let massToVolume: Bool
        public init(operand: Quantity, ingredient: String,
                    target: UnitExpr, massToVolume: Bool) {
            self.operand = operand
            self.ingredient = ingredient
            self.target = target
            self.massToVolume = massToVolume
        }
    }

    private static func isMass(_ q: Quantity) -> Bool {
        q.display.isLinear
            && q.display.vector.l == 0 && q.display.vector.m == 1
            && q.display.vector.t == 0 && q.display.vector.a == 0
            && q.display.vector.i == 0
    }
    private static func isVolume(_ q: Quantity) -> Bool {
        q.display.isLinear
            && q.display.vector.l == 3 && q.display.vector.m == 0
            && q.display.vector.t == 0 && q.display.vector.a == 0
            && q.display.vector.i == 0
    }

    /// The shape match (nil = not a density phrase — other lanes
    /// decide).
    public static func match(_ line: String, context: NumberFormatContext,
                             unitContext: UnitContext,
                             env: TypedEnv = TypedEnv()) -> Match? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let tokens = MixedUnitScanner.tokenize(trimmed, context: context,
                                                     unitContext: unitContext,
                                                     env: env) else { return nil }
        guard tokens.count == 5 || tokens.count == 6 else { return nil }
        // tokens[0]: the mass/volume quantity
        guard case .quantity(let q, range: _) = tokens[0] else { return nil }
        let kind: Bool? = isMass(q) ? true : (isVolume(q) ? false : nil)
        guard let massToVolume = kind else { return nil }
        // tokens[1]: the `of` operator
        guard case .op(let o, range: _) = tokens[1], o == "of" else { return nil }
        // tokens[2..]: one or two ingredient words
        var ingredientWords: [String] = []
        let keywordIndex = tokens.count - 2
        var i = 2
        while i < keywordIndex {
            guard tokens.indices.contains(i),
                  case .word(let w, range: _) = tokens[i] else { return nil }
            ingredientWords.append(w)
            i += 1
        }
        guard ingredientWords.count == keywordIndex - 2 else { return nil }
        let ingredient = ingredientWords.joined(separator: " ")
        guard CookingDensities.entry(named: ingredient) != nil else {
            return nil
        }
        // keyword
        guard tokens.indices.contains(keywordIndex),
              case .word(let kw, range: _) = tokens[keywordIndex],
              kw == "to" || kw == "in" || kw == "as" else { return nil }
        // target: a bare linear unit. A target of the SAME kind as
        // the operand is a plain unit conversion (`2 tbsp of oil to
        // ml` — the density is irrelevant); the OPPOSITE kind goes
        // through the ingredient density.
        guard tokens.indices.contains(tokens.count - 1),
              case .unit(let t, range: _) = tokens[tokens.count - 1],
              t.isLinear else { return nil }
        guard isMassExpr(t) || isVolExpr(t) else { return nil }
        return Match(operand: q, ingredient: ingredient, target: t,
                     massToVolume: massToVolume)
    }

    private static func isMassExpr(_ u: UnitExpr) -> Bool {
        u.isLinear && u.vector.l == 0 && u.vector.m == 1
            && u.vector.t == 0 && u.vector.a == 0 && u.vector.i == 0
    }
    private static func isVolExpr(_ u: UnitExpr) -> Bool {
        u.isLinear && u.vector.l == 3 && u.vector.m == 0
            && u.vector.t == 0 && u.vector.a == 0 && u.vector.i == 0
    }

    /// The owned conversion (the phrase matched — result or strict
    /// error).
    public static func convert(_ m: Match, decimalPlaces: Int) -> LineResult {
        let dp = max(decimalPlaces, 10)
        guard let base = m.operand.baseValue, base.isFinite,
              m.target.toBase > 0, m.target.isLinear
        else { return .error(message: "Incompatible units") }
        let sameKind = m.massToVolume ? isMassExpr(m.target) : isVolExpr(m.target)
        let value: Double
        if sameKind {
            // Same kind on both sides: a plain unit conversion (the
            // density is irrelevant; base units are shared).
            value = base
        } else {
            guard let rho = CookingDensities.kgPerM3(named: m.ingredient),
                  rho.isFinite, rho > 0 else {
                return .error(message: "Unknown ingredient")
            }
            // mass -> volume: kg / (kg/m³) = m³; volume -> mass:
            // m³ × (kg/m³) = kg.
            value = m.massToVolume ? (base / rho) : (base * rho)
        }
        guard value.isFinite else { return .error(message: "Invalid expression") }
        let v = value / m.target.toBase
        guard v.isFinite else { return .error(message: "Invalid expression") }
        return .number(value: roundResult(v, decimalPlaces: dp),
                       unit: m.target.label)
    }

    /// Convenience entry: match + convert (nil when the line is not a
    /// density phrase).
    public static func tryConvert(_ line: String, context: NumberFormatContext,
                                  unitContext: UnitContext,
                                  decimalPlaces: Int,
                                  env: TypedEnv = TypedEnv()) -> LineResult? {
        guard let m = match(line, context: context, unitContext: unitContext,
                            env: env) else { return nil }
        return convert(m, decimalPlaces: decimalPlaces)
    }
}
