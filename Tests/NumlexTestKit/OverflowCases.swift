import Foundation
import NumlexCore

/// Crash-boundary coverage for huge and non-finite numeric values.
/// The engine must never trap: oversized literals and arithmetic
/// overflow are rejected as generic errors, large FINITE values are
/// evaluated and displayed scientifically, and the shared formatter is
/// total over all Double inputs (NaN/±∞ included).
public let overflowCases: [EngineCase] = [
    EngineCase("overflow-reported-crash-case") {
        // The exact persisted line from the crash report: 5e13 kg ×
        // 1e6 mg/kg = 5e19 — finite, above Int64.max (≈9.22e18), must
        // evaluate and display as `5e+19 mg` without touching any
        // Int64 cast (the old code trapped exactly here).
        var vars: [String: Double] = [:]
        guard let r = evalLine("50000000000000 kg to mg", variables: &vars,
                               rates: Rates(), decimalPlaces: 7) else {
            throw CaseFailure(message: "conversion must evaluate", location: "OverflowCases")
        }
        guard case .number(let v, let u) = r else {
            throw CaseFailure(message: "must be a conversion number, got \(r)",
                              location: "OverflowCases")
        }
        try expect(v.isFinite, "result finite")
        try expectEqual(v, 5e19, "5e19 value")
        try expectEqual(u ?? "<none>", "mg", "mg unit")
        try expect(v > 9223372036854775807, "above Int64.max (the trap zone)")
        try expectEqual(formatDisplayValue(v, decimalPlaces: 7), "5e+19",
                        "documented scientific display")
        // The legacy alias must be safe on the same value.
        try expectEqual(formatNumberForDisplay(v), "5e+19", "alias formatter")
    },

    EngineCase("overflow-large-finite-scientific") {
        // |v| >= 1e16 → deterministic compact scientific notation.
        try expectEqual(formatDisplayValue(1e16, decimalPlaces: 7), "1e+16", "threshold")
        try expectEqual(formatDisplayValue(9.3e18, decimalPlaces: 7), "9.3e+18", "near Int64.max")
        try expectEqual(formatDisplayValue(1e19, decimalPlaces: 7), "1e+19", "above Int64.max")
        try expectEqual(formatDisplayValue(-5e22, decimalPlaces: 7), "-5e+22", "negative")
        try expectEqual(formatDisplayValue(1.5e21, decimalPlaces: 7), "1.5e+21", "mantissa kept")
        // Degenerate tiny negative: trimmed exactly as the legacy code
        // did ("-0") — behavior preserved, no trap.
        try expectEqual(formatDisplayValue(-2.5e-200, decimalPlaces: 7), "-0",
                        "tiny negative trims as before")
        // The largest finite Double: no trap, stable 7-digit mantissa.
        try expectEqual(formatDisplayValue(.greatestFiniteMagnitude, decimalPlaces: 7),
                        "1.797693e+308", "greatestFiniteMagnitude")
        // Int64.max as a Double rounds ABOVE Int64.max — it must take
        // the scientific path, never the Int64 cast.
        try expectEqual(formatDisplayValue(9223372036854775807, decimalPlaces: 7),
                        "9.223372e+18", "Int64.max boundary")
    },

    EngineCase("overflow-int64-and-double-boundaries") {
        // Below the 1e16 threshold: exact integer comma grouping, both
        // sides of the Double-exactness boundary (2^53).
        try expectEqual(formatDisplayValue(1_663, decimalPlaces: 7), "1,663", "small integral")
        try expectEqual(formatDisplayValue(9007199254740991, decimalPlaces: 7),
                        "9,007,199,254,740,991", "2^53-1 exact")
        try expectEqual(formatDisplayValue(9007199254740992, decimalPlaces: 7),
                        "9,007,199,254,740,992", "2^53")
        try expectEqual(formatDisplayValue(9999999999999998, decimalPlaces: 7),
                        "9,999,999,999,999,998", "just under 1e16")
        try expectEqual(formatDisplayValue(1e16, decimalPlaces: 7), "1e+16", "just at 1e16")
    },

    EngineCase("overflow-nonfinite-formatter-safe") {
        try expectEqual(formatDisplayValue(.nan, decimalPlaces: 7), "NaN", "NaN")
        try expectEqual(formatDisplayValue(.infinity, decimalPlaces: 7), "+∞", "+infinity")
        try expectEqual(formatDisplayValue(-.infinity, decimalPlaces: 7), "-∞", "-infinity")
        // Scientific helper is total on the same inputs' magnitudes.
        try expectEqual(scientificNotation(5e22), "5e+22", "sci 5e+22")
        try expectEqual(scientificNotation(-1.5e21), "-1.5e+21", "sci negative")
    },

    EngineCase("overflow-normal-formatting-unchanged") {
        try expectEqual(formatDisplayValue(0, decimalPlaces: 7), "0", "zero")
        try expectEqual(formatDisplayValue(-5, decimalPlaces: 7), "-5", "negative integral")
        try expectEqual(formatDisplayValue(0.5, decimalPlaces: 7), "0.5", "decimal")
        try expectEqual(formatDisplayValue(0.123456789, decimalPlaces: 7), "0.1234568",
                        "configured decimalPlaces rounding")
        try expectEqual(formatDisplayValue(16.0934, decimalPlaces: 7), "16.0934",
                        "trailing-zero trimming")
        try expectEqual(formatDisplayValue(0.0001, decimalPlaces: 7), "0.0001", "small decimal")
        try expectEqual(formatDisplayValue(1e-5, decimalPlaces: 7), "0.00001", "1e-5")
        try expectEqual(formatDisplayValue(212, decimalPlaces: 7), "212", "temperature-ish")
        // decimalPlaces is honored by callers that configure it.
        try expectEqual(formatDisplayValue(0.123456789, decimalPlaces: 3), "0.123",
                        "decimalPlaces=3")
    },

    EngineCase("overflow-oversized-literals-error") {
        var vars: [String: Double] = [:]
        // 310 digits: Double(...) is +∞ — rejected at the tokenizer.
        // (309 digits, 1e308, is still finite and must NOT be rejected.)
        let huge = "1" + String(repeating: "0", count: 309)
        let r1 = evalLine("\(huge) + 1", variables: &vars, rates: Rates(), decimalPlaces: 7)
        guard case .error? = r1 else {
            throw CaseFailure(message: "300-digit literal must be an error, got \(String(describing: r1))",
                              location: "OverflowCases")
        }
        // Conversion-shaped line with an unusable number: generic hidden
        // error, never a .number.
        let r2 = evalLine("\(huge) kg to mg", variables: &vars, rates: Rates(), decimalPlaces: 7)
        guard case .error? = r2 else {
            throw CaseFailure(message: "oversized conversion number must be an error, got \(String(describing: r2))",
                              location: "OverflowCases")
        }
        // Assignment with an oversized literal: error AND nothing stored.
        let r3 = evalLine("big = \(huge)", variables: &vars, rates: Rates(), decimalPlaces: 7)
        guard case .error? = r3 else {
            throw CaseFailure(message: "oversized assignment must be an error, got \(String(describing: r3))",
                              location: "OverflowCases")
        }
        try expect(vars["big"] == nil, "non-finite never stored")
    },

    EngineCase("overflow-expression-overflow-errors") {
        var vars: [String: Double] = [:]
        // pow overflow: 10^400 = +∞ → explicit parse error.
        let r1 = evalLine("10 ^ 400", variables: &vars, rates: Rates(), decimalPlaces: 7)
        guard case .error? = r1 else {
            throw CaseFailure(message: "10 ^ 400 must be an error, got \(String(describing: r1))",
                              location: "OverflowCases")
        }
        // Multiplication overflow: 1e300 × 1e300 = 1e600 = +∞.
        let big = "1" + String(repeating: "0", count: 300)
        let r2 = evalLine("\(big) × \(big)", variables: &vars, rates: Rates(), decimalPlaces: 7)
        guard case .error? = r2 else {
            throw CaseFailure(message: "1e300 × 1e300 must be an error, got \(String(describing: r2))",
                              location: "OverflowCases")
        }
        // Assignment overflow: error and nothing stored.
        let r3 = evalLine("x = 10 ^ 400", variables: &vars, rates: Rates(), decimalPlaces: 7)
        guard case .error? = r3 else {
            throw CaseFailure(message: "x = 10 ^ 400 must be an error, got \(String(describing: r3))",
                              location: "OverflowCases")
        }
        try expect(vars["x"] == nil, "overflowing assignment never stored")
        // Division by zero keeps its existing explicit semantics.
        let r4 = evalLine("1 / 0", variables: &vars, rates: Rates(), decimalPlaces: 7)
        guard case .error? = r4 else {
            throw CaseFailure(message: "1 / 0 must stay an error, got \(String(describing: r4))",
                              location: "OverflowCases")
        }
    },

    EngineCase("overflow-conversion-large-finite-still-works") {
        // Do NOT reject large FINITE values: 1e36 kg → 1e42 mg.
        var vars: [String: Double] = [:]
        let big = "1" + String(repeating: "0", count: 36) // 1e36, finite
        let r = evalLine("\(big) kg to mg", variables: &vars, rates: Rates(), decimalPlaces: 7)
        guard case .number(let v, let u)? = r else {
            throw CaseFailure(message: "1e36 kg to mg must evaluate, got \(String(describing: r))",
                              location: "OverflowCases")
        }
        try expectEqual(v, 1e42, "1e42 finite")
        try expectEqual(u ?? "<none>", "mg", "mg unit")
        try expectEqual(formatDisplayValue(v, decimalPlaces: 7), "1e+42", "scientific display")
    },

    EngineCase("overflow-conversion-overflow-errors") {
        var vars: [String: Double] = [:]
        // 1e308 kg × 1e6 = 1e314 = +∞ → generic hidden error.
        let huge = "1" + String(repeating: "0", count: 308)
        let r = evalLine("\(huge) kg to mg", variables: &vars, rates: Rates(), decimalPlaces: 7)
        guard case .error? = r else {
            throw CaseFailure(message: "1e308 kg to mg must be an error, got \(String(describing: r))",
                              location: "OverflowCases")
        }
    },

    EngineCase("overflow-nonfinite-rates-never-number") {
        // Non-finite rates: generic error, never a .number.
        var vars: [String: Double] = [:]
        let inf = evalLine("10 USD to RUB", variables: &vars,
                           rates: Rates(USD: .infinity), decimalPlaces: 7)
        guard case .error? = inf else {
            throw CaseFailure(message: "infinite rate must be an error, got \(String(describing: inf))",
                              location: "OverflowCases")
        }
        let nan = evalLine("10 USD to RUB", variables: &vars,
                           rates: Rates(USD: .nan), decimalPlaces: 7)
        guard case .error? = nan else {
            throw CaseFailure(message: "NaN rate must be an error, got \(String(describing: nan))",
                              location: "OverflowCases")
        }
        // Overflow through a rate: 1e308 × 90 = +∞.
        let big = "1" + String(repeating: "0", count: 308)
        let ovf = evalLine("\(big) USD to RUB", variables: &vars,
                           rates: Rates(USD: 90), decimalPlaces: 7)
        guard case .error? = ovf else {
            throw CaseFailure(message: "rate overflow must be an error, got \(String(describing: ovf))",
                              location: "OverflowCases")
        }
        // Ordinary rates are untouched.
        let ok = evalLine("10 USD to RUB", variables: &vars,
                          rates: Rates(USD: 90), decimalPlaces: 7)
        guard case .number(let v, let u)? = ok else {
            throw CaseFailure(message: "10 USD to RUB @90 must work, got \(String(describing: ok))",
                              location: "OverflowCases")
        }
        try expectEqual(v, 900, "900")
        try expectEqual(u ?? "<none>", "RUB", "RUB")
    },

    EngineCase("overflow-total-through-shared-formatter") {
        // The Total path sums raw Doubles and feeds the shared
        // formatter; an overflowing sum (inf) must format without
        // trapping, and near-overflow finite sums keep working.
        let sumOverflow = 1e308 + 1e308
        try expect(sumOverflow.isInfinite, "sum overflows to +∞")
        try expectEqual(formatDisplayValue(sumOverflow, decimalPlaces: 7), "+∞",
                        "overflowing Total formats safely")
        let sumFinite = 1e308 + 5e22
        try expect(sumFinite.isFinite, "near-overflow sum finite")
        try expectEqual(formatDisplayValue(sumFinite, decimalPlaces: 7), "1e+308",
                        "near-overflow Total formats scientifically")
    },
]
