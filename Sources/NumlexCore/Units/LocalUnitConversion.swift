import Foundation

/// The measurement system the app auto-converts stand-alone quantities
/// towards. Derived (never persisted) from the macOS locale; the pure
/// conversion policy is injectable, so tests and validation launches can
/// pin metric/US/UK deterministically.
public enum LocalUnitSystem: String, Codable, CaseIterable, Sendable, Equatable {
    case metric
    case us
    case uk

    /// The picker/test order.
    public static let uiOrder: [LocalUnitSystem] = [.metric, .us, .uk]

    /// Tolerant decode: a missing or unknown raw value is metric.
    public static func resolve(_ raw: String?) -> LocalUnitSystem {
        guard let raw, let v = LocalUnitSystem(rawValue: raw) else { return .metric }
        return v
    }

    /// The macOS measurement system the app derives the target from.
    /// `.us` and `.uk` map to themselves; everything else (metric and any
    /// future identifier) is metric.
    public static func from(_ measurementSystem: Locale.MeasurementSystem) -> LocalUnitSystem {
        switch measurementSystem {
        case .us: return .us
        case .uk: return .uk
        default: return .metric
        }
    }
}

/// Automatic conversion of a strict STAND-ALONE quantity to the local
/// measurement system (Settings → Numbers → Auto-convert single units).
///
/// This is an EVALUATION-context feature, never text rewriting: only the
/// evaluated `.number` result of a line that is exactly one numeric
/// literal plus one atomic built-in physical unit is converted — the
/// source text, line IDs, references and the store stay byte-identical.
/// A `nil` system (the default, "Off") returns every quantity untouched,
/// so the feature is byte-for-byte the previous behavior when disabled.
public enum LocalUnitConversion {

    /// The locale-sensitive physical families this policy owns. Every
    /// other dimension (time/calendar, angle, data, energy, torque,
    /// luminous/activity/dose, pixels, currency) has no locale
    /// convention and is left exactly as typed.
    public enum Family: Equatable, Sendable {
        case length, mass, volume, area, speed, acceleration
        case temperature, pressure, density, fuel
    }

    // MARK: - Eligibility

    /// Whether `unit` is one ATOMIC BUILT-IN unit: a single catalog atom
    /// (never a compound expression such as `km/h` or `kg/m³`) that the
    /// built-in catalog — not a user custom unit — resolves.
    public static func isAtomicBuiltIn(_ unit: UnitExpr, unitContext: UnitContext) -> Bool {
        guard !unit.label.isEmpty else { return false }
        // ONE catalog atom: the label must resolve through the ATOMIC
        // token lookup (aliases, plural, prefix folding). A composed
        // expression the user typed (`m²/s`, `km/L`) has no such atom and
        // is rejected; an atom whose own label contains an operator
        // (`km/h`, `kg/m³`, `m/s²`) is still one atom and stays eligible.
        guard let atom = UnitCatalog.resolveToken(unit.label),
              UnitCatalog.expr(of: atom) == unit else { return false }
        // A custom unit with the same label shadows the built-in one in
        // the evaluation context: it is never auto-converted.
        if let contextAtom = unitContext.resolveToken(unit.label),
           contextAtom.id != atom.id {
            return false
        }
        return true
    }

    /// The locale-sensitive family of an atomic unit, or nil when the
    /// dimension has no locale convention.
    public static func family(of unit: UnitExpr) -> Family? {
        switch unit.kind {
        case .temperature: return .temperature
        case .fuel: return .fuel
        case .currency: return nil
        case .factor(let vector, _):
            if unit.family == .density { return .density }
            guard unit.family == .none else { return nil }
            switch (vector.l, vector.m, vector.t, vector.a, vector.i) {
            case (1, 0, 0, 0, 0): return .length
            case (0, 1, 0, 0, 0): return .mass
            case (3, 0, 0, 0, 0): return .volume
            case (2, 0, 0, 0, 0): return .area
            case (1, 0, -1, 0, 0): return .speed
            // Acceleration uses the catalog's L²/T² vector (the
            // m-per-s2 / ft-per-s2 / standard-gravity atom family).
            case (2, 0, -2, 0, 0): return .acceleration
            case (-1, 1, -2, 0, 0): return .pressure
            default: return nil
            }
        }
    }

    // MARK: - Deterministic targets

    /// The target unit LABEL for a family, the measurement system and the
    /// quantity's magnitude in BASE units (m, kg, m³, m², m/s, m/s², K,
    /// Pa, kg/m³, L/m). The smaller/larger unit is chosen by that
    /// magnitude so `3 km` under US becomes `~1.86 mi` and `5 kg`
    /// becomes `~11.02 lb`. nil = unsupported family.
    public static func targetLabel(for family: Family,
                                   system: LocalUnitSystem,
                                   baseMagnitude: Double) -> String? {
        let m = baseMagnitude.isFinite ? abs(baseMagnitude) : .nan
        switch family {
        case .length:
            // Base: meter.
            switch system {
            case .metric: return m < 0.01 ? "mm" : (m < 1 ? "cm" : (m < 1000 ? "m" : "km"))
            case .us: return m < 0.3048 ? "in" : (m < 1609.344 ? "ft" : "mi")
            case .uk: return m < 1 ? "cm" : (m < 1609.344 ? "m" : "mi")
            }
        case .mass:
            // Base: kilogram.
            switch system {
            case .metric, .uk: return m < 1 ? "g" : "kg"
            case .us: return m < 0.45359237 ? "oz" : "lb"
            }
        case .volume:
            // Base: cubic meter; liters = m³ / 0.001.
            switch system {
            case .metric: return m < 0.001 ? "ml" : "L"
            case .us: return m < 0.003785411784 ? "fl oz" : "gal"
            case .uk: return m < 0.00454609 ? "uk fl oz" : "uk gal"
            }
        case .area:
            // Base: square meter.
            switch system {
            case .metric: return m < 0.01 ? "cm²" : (m < 1_000_000 ? "m²" : "km²")
            case .us: return m < 0.09290304 ? "in²" : (m < 2_589_988.110336 ? "ft²" : "mi²")
            case .uk: return m < 0.01 ? "cm²" : (m < 2_589_988.110336 ? "m²" : "mi²")
            }
        case .speed:
            return system == .metric ? "km/h" : "mph"
        case .acceleration:
            return system == .us ? "ft/s²" : "m/s²"
        case .temperature:
            return system == .us ? "F°" : "C°"
        case .pressure:
            return system == .us ? "psi" : "kPa"
        case .density:
            return system == .us ? "lb/ft³" : "kg/m³"
        case .fuel:
            switch system {
            case .metric: return "L/100km"
            case .us: return "US mpg"
            case .uk: return "UK mpg"
            }
        }
    }

    // MARK: - Application

    /// The result quantity of one shape-owned mixed-unit line after the
    /// optional automatic conversion. With `localUnits == nil` (Off) the
    /// quantity is returned unchanged — byte-for-byte the previous
    /// behavior.
    public static func applied(to quantity: Quantity,
                               line: String,
                               localUnits: LocalUnitSystem?,
                               context: NumberFormatContext,
                               unitContext: UnitContext,
                               env: TypedEnv) -> Quantity {
        guard let localUnits,
              let source = MixedUnitLine.standaloneQuantity(
                line, context: context, unitContext: unitContext, env: env),
              source.display == quantity.display || source.value == quantity.value,
              let family = family(of: quantity.display),
              let base = quantity.baseValue
        else { return quantity }
        guard let label = targetLabel(for: family, system: localUnits,
                                      baseMagnitude: base) else { return quantity }
        guard let target = UnitCatalog.resolveExpression(label)?.unit else { return quantity }
        // Already the local unit: identity, never a floating round-trip.
        if target.kind == quantity.display.kind,
           target.vector == quantity.display.vector,
           target.family == quantity.display.family,
           target.toBase == quantity.display.toBase {
            return quantity
        }
        guard let converted = convertValue(quantity.value,
                                           from: quantity.display,
                                           to: target,
                                           rates: Rates()) else { return quantity }
        var out = quantity
        out.value = converted.value
        out.display = target
        out.presentation = .standard
        return out
    }
}

extension MixedUnitLine {
    /// The STRICT stand-alone-quantity probe (Auto-convert eligibility):
    /// the whole line is exactly ONE `<number> <unit>` literal whose unit
    /// is a single atomic built-in physical unit. Everything else is
    /// rejected here — assignments, named values, answer tokens, an
    /// explicit `to`/`in`/`as` target, arithmetic/rates/compounds, money
    /// and currency, custom units, comments and headings, temporal/angle/
    /// data dimensions and unconfigured dimensions.
    static func standaloneQuantity(_ line: String,
                                   context: NumberFormatContext,
                                   unitContext: UnitContext,
                                   env: TypedEnv) -> Quantity? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard !trimmed.hasPrefix("#"), !trimmed.hasPrefix("//") else { return nil }
        guard !BooleanLogic.hasAssignment(line) else { return nil }
        guard !(line as NSString).contains("\u{FFFC}") else { return nil }
        let (body, target) = Self.splitTarget(line)
        guard target == nil,
              body.trimmingCharacters(in: .whitespaces) == trimmed else { return nil }
        guard let tokens = MixedUnitScanner.tokenize(body, context: context,
                                                     unitContext: unitContext,
                                                     env: env) else { return nil }
        // Exactly ONE quantity literal, optionally preceded by ONE
        // unary sign (`-5 kg` is still a single literal; `5 kg - 2 kg`
        // is arithmetic and stays out).
        let quantityToken: MToken?
        switch tokens.count {
        case 1: quantityToken = tokens[0]
        case 2:
            if case .op(let sign, range: let r) = tokens[0], sign == "-" || sign == "+",
               r.location == 0 {
                quantityToken = tokens[1]
            } else {
                quantityToken = nil
            }
        default: quantityToken = nil
        }
        guard let quantityToken,
              case .quantity(let quantity, range: _) = quantityToken else { return nil }
        guard LocalUnitConversion.isAtomicBuiltIn(quantity.display,
                                                  unitContext: unitContext),
              LocalUnitConversion.family(of: quantity.display) != nil else { return nil }
        return quantity
    }
}
