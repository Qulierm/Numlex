import Foundation

/// A hashable vector of integer exponents over the FIVE physical base
/// dimensions (length L, mass M, time T, electric current A, luminous
/// intensity I). Temperature, currency and fuel economy are NOT base
/// dimensions: they are special unit kinds handled by finite transforms
/// (see `UnitKind`), so they never appear in a vector.
///
/// Dimensionless quantities (radians, bits, hertz, ...) carry the zero
/// vector and are disambiguated by `UnitFamily` so that, for example,
/// bits never silently convert to radians and newton-meters (torque)
/// never convert to joules (energy).
public struct DimensionVector: Hashable, Sendable, Equatable {
    public var l: Int8
    public var m: Int8
    public var t: Int8
    public var a: Int8
    public var i: Int8

    public init(l: Int8 = 0, m: Int8 = 0, t: Int8 = 0, a: Int8 = 0, i: Int8 = 0) {
        self.l = l
        self.m = m
        self.t = t
        self.a = a
        self.i = i
    }

    /// The zero vector (dimensionless).
    public static let zero = DimensionVector()

    public var isDimensionless: Bool { self == .zero }

    /// Multiplication of quantities (exponents add).
    public static func * (lhs: DimensionVector, rhs: DimensionVector) -> DimensionVector {
        DimensionVector(l: lhs.l + rhs.l, m: lhs.m + rhs.m, t: lhs.t + rhs.t,
                        a: lhs.a + rhs.a, i: lhs.i + rhs.i)
    }

    /// Division of quantities (exponents subtract).
    public static func / (lhs: DimensionVector, rhs: DimensionVector) -> DimensionVector {
        DimensionVector(l: lhs.l - rhs.l, m: lhs.m - rhs.m, t: lhs.t - rhs.t,
                        a: lhs.a - rhs.a, i: lhs.i - rhs.i)
    }

    /// Integer power. Exponents are bounded so a `^2`/`^3` of a legal
    /// unit can never overflow Int8; callers guard the power first.
    public func powered(_ n: Int) -> DimensionVector {
        guard n >= 0, n <= 3 else { return self }
        let e = Int8(n)
        return DimensionVector(l: l &* e, m: m &* e, t: t &* e, a: a &* e, i: i &* e)
    }
}

/// Disambiguation tag for dimensionless (and one shared-vector) unit
/// families. Two linear units convert to each other only when BOTH the
/// dimension vector and the family match, which keeps dimensionally
/// identical but physically different quantities apart:
/// - `.angle`: rad, degree, gradian, turn, arcmin, arcsec (1-free);
/// - `.data`: bit/byte and their decimal/binary prefixes;
/// - `.energy` vs `.torque`: both M·L²/T², never convertible;
/// - `.activity` (Bq, Ci) vs plain 1/T frequency (Hz, rpm);
/// - `.absorbedDose` (Gy, rad) / `.doseEquivalent` (Sv, rem) vs power;
/// - `.luminousIntensity` (cd) vs `.luminousFlux` (lm, lux).
public enum UnitFamily: Hashable, Sendable, CaseIterable {
    case none
    case angle
    case data
    case energy
    case torque
    case activity
    case absorbedDose
    case doseEquivalent
    case luminousIntensity
    case luminousFlux
    case fuel
}

/// The finite-transform kind of a unit. Everything that is not a pure
/// linear factor gets an explicit kind so conversion is ALWAYS a
/// declared finite transform:
/// - `.factor`: one unit = `factor` base units (exact values);
/// - `.temperature`: affine C/F/K/Rankine transforms;
/// - `.currency`: ISO code, converted through the live rate table;
/// - `.fuel`: fuel economy in the pseudo-dimension `.fuel` —
///   `reciprocal == false` is a consumption form (L/100km:
///   value × factor = base L/m) and `reciprocal == true` an economy
///   form (km/L, mpg: factor / value = base L/m).
public enum UnitKind: Hashable, Sendable {
    case factor(DimensionVector, Double)
    case temperature(TemperatureUnit)
    case currency(String)
    case fuel(factor: Double, reciprocal: Bool)

    /// The conversion class of the kind: two units can only be converted
    /// within the same class.
    public var conversionClass: ConversionClass {
        switch self {
        case .factor: return .linear
        case .temperature: return .temperature
        case .currency: return .currency
        case .fuel: return .fuel
        }
    }
}

public enum ConversionClass: Hashable, Sendable {
    case linear, temperature, currency, fuel
}

/// Temperature unit for the affine transform family. Base: kelvin.
public enum TemperatureUnit: Hashable, Sendable, CaseIterable {
    case celsius, fahrenheit, kelvin, rankine

    /// value → kelvin (finite for every finite input).
    public func toKelvin(_ v: Double) -> Double {
        switch self {
        case .celsius: return v + 273.15
        case .fahrenheit: return (v - 32.0) * 5.0 / 9.0 + 273.15
        case .kelvin: return v
        case .rankine: return v * 5.0 / 9.0
        }
    }

    /// kelvin → value (finite for every finite input).
    public func fromKelvin(_ k: Double) -> Double {
        switch self {
        case .celsius: return k - 273.15
        case .fahrenheit: return (k - 273.15) * 9.0 / 5.0 + 32.0
        case .kelvin: return k
        case .rankine: return k * 9.0 / 5.0
        }
    }
}
