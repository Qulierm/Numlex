import Foundation
import NumlexCore

/// End-to-end coverage of the rich conversion grammar: compound units
/// (`km/h`, `kg/m³`, `N·m`), exponents, affine temperature (C/F/K/R),
/// reciprocal fuel economy, case-sensitive data, grouped/scientific
/// numbers, and the approved QA targets with their exact values.

private func richEval(_ line: String,
                      rates: Rates = Rates()) -> LineResult? {
    var vars: [String: Double] = [:]
    return evalLine(line, variables: &vars, rates: rates, decimalPlaces: 7)
}

private func expectRich(_ line: String, _ value: Double, _ unit: String,
                        tolerance: Double = 0.0001,
                        rates: Rates = Rates()) throws {
    guard let r = richEval(line, rates: rates),
          case .number(let v, let u) = r else {
        throw CaseFailure(message: "\(line) must be a conversion, got \(String(describing: richEval(line, rates: rates)))",
                          location: "RichConversionCases")
    }
    try expectClose(v, value, tolerance, "\(line) value")
    try expectEqual(u ?? "<none>", unit, "\(line) unit")
}

private func expectRichError(_ line: String) throws {
    let r = richEval(line)
    guard case .error = r else {
        throw CaseFailure(message: "\(line) must be an error, got \(String(describing: r))",
                          location: "RichConversionCases")
    }
}

public let richConversionCases: [EngineCase] = [
    // MARK: Approved QA targets

    EngineCase("rich-qa-mph-to-kmh") {
        try expectRich("60 mph to km/h", 96.56064, "km/h")
    },
    EngineCase("rich-qa-m2-to-ft2") {
        try expectRich("10 m2 to ft²", 107.639104, "ft²")
    },
    EngineCase("rich-qa-psi-to-bar") {
        try expectRich("30 psi to bar", 2.068427, "bar")
    },
    EngineCase("rich-qa-gb-to-mib") {
        try expectRich("5 GB to MiB", 4768.371582, "MiB")
    },
    EngineCase("rich-qa-gal-to-l") {
        try expectRich("1 gal to L", 3.785411784, "L", tolerance: 1e-9)
    },
    EngineCase("rich-qa-ukgal-to-l") {
        try expectRich("1 uk_gal to L", 4.54609, "L", tolerance: 1e-9)
    },

    // MARK: Temperature (affine C / F / K / R)

    EngineCase("rich-temperature") {
        try expectRich("100 C to F", 212, "F°")
        try expectRich("32 F to C", 0, "C°")
        try expectRich("273.15 K to C", 0, "C°")
        try expectRich("0 C to R", 491.67, "R°")
        try expectRich("0 K to R", 0, "R°")
        try expectRich("-279.67 F to K", 100, "K°", tolerance: 0.001)
        try expectRich("273.15 C to R", 983.34, "R°")
    },

    // MARK: Length / area / volume

    EngineCase("rich-length") {
        try expectRich("1 mi to ft", 5280, "ft")
        try expectRich("1 m to in", 39.37007874015748, "in")
        try expectRich("1 in. to cm", 2.54, "cm")
        try expectRich("5 nautical miles to km", 9.26, "km")
        try expectRich("1 kn to km/h", 1.852, "km/h")
        try expectRich("1 ly to pc", 0.3066013938668485, "pc")
        try expectRich("1 parsec to ly", 3.2615637771677165, "ly")
    },
    EngineCase("rich-area") {
        try expectRich("100 ft² to m²", 9.290304, "m²")
        try expectRich("1 acre to m²", 4046.8564224, "m²")
        try expectRich("1 ha to acres", 2.4710538146716535, "acre")
        try expectRich("10 m² to ft2", 107.639104, "ft²")
    },
    EngineCase("rich-volume") {
        try expectRich("1 gal to qt", 4, "qt")
        try expectRich("1 uk gal to uk pt", 8, "uk pt")
        try expectRich("1 tbsp to fl oz", 0.5, "fl oz")
        try expectRich("1 cup to fl oz", 8, "fl oz")
        try expectRich("1 uk pt to uk fl oz", 20, "uk fl oz")
        try expectRich("1 ft³ to L", 28.316846592, "L")
        try expectRich("1 in³ to mL", 16.387064, "ml")
    },
    EngineCase("rich-mass") {
        try expectRich("1 lb to oz", 16, "oz")
        try expectRich("1 st to lb", 14, "lb")
        try expectRich("1 long ton to kg", 1016.0469088, "kg")
        try expectRich("1 short ton to kg", 907.18474, "kg")
        try expectRich("1 grain to g", 0.06479891, "g")
        try expectRich("1 oz to g", 28.349523125, "g")
    },

    // MARK: Compound units

    EngineCase("rich-compound-speed") {
        try expectRich("10 km/h to m/s", 2.7777777777777777, "m/s")
        try expectRich("5 ft/s to m/s", 1.524, "m/s")
        try expectRich("1 mph to kn", 0.8689762347816137, "kn")
    },
    EngineCase("rich-compound-acceleration") {
        try expectRich("1 km/h/s to m/s²", 0.2777777777777778, "m/s²")
        try expectRich("1 m/s² to g0", 0.10197162129779283, "g₀")
    },
    EngineCase("rich-compound-density") {
        try expectRich("5 kg/m³ to lb/ft³", 0.3121494311317898, "lb/ft³")
        try expectRich("1 g/cm³ to kg/m³", 1000, "kg/m³")
    },
    EngineCase("rich-pressure") {
        try expectRich("1 psi to Pa", 6894.757293168, "Pa")
        try expectRich("1 atm to bar", 1.01325, "bar")
        try expectRich("1 torr to Pa", 133.32236842105263, "Pa")
    },
    EngineCase("rich-force-torque-energy") {
        try expectRich("1 lbf to N", 4.4482216152605, "N")
        try expectRich("1 kgf to N", 9.80665, "N")
        try expectRich("1 lbf·in to N·m", 0.1129848290276167, "N·m")
        try expectRich("1 ft·lbf to J", 1.3558179483314004, "J")
        try expectRichError("5 lbf·ft to ft·lbf")
        try expectRich("1 BTU to J", 1055.05585262, "J")
        try expectRich("1 kWh to Wh", 1000, "Wh")
        try expectRich("1 kcal to J", 4184, "J")
        try expectRich("1 hp to W", 745.6998715822702, "W")
        try expectRich("1 eV to J", 1.602176634e-19, "J", tolerance: 1e-28)
    },

    // MARK: Angle / frequency / flow / electrical / nuclear

    EngineCase("rich-angle") {
        try expectRich("1 turn to deg", 360, "deg")
        try expectRich("1 arcmin to deg", 1.0 / 60, "deg")
        try expectRich("180 deg to rad", 3.141592653589793, "rad")
    },
    EngineCase("rich-frequency") {
        try expectRich("1 Hz to rpm", 60, "rpm")
        try expectRich("1200 rpm to Hz", 20, "Hz")
    },
    EngineCase("rich-flow") {
        try expectRich("1 gpm to L/min", 3.785411784, "L/min")
        try expectRich("1 cfs to m³/s", 0.028316846592, "m³/s")
        try expectRich("10 L/min to L/s", 0.16666666666666666, "L/s")
    },
    EngineCase("rich-electrical") {
        try expectRich("1 Ah to coulomb", 3600, "C")
        try expectRich("1 mAh to coulomb", 3.6, "C")
        try expectRich("1 mA to A", 0.001, "A")
        try expectRich("1 kV to V", 1000, "V")
        try expectRich("1 MΩ to Ω", 1000000, "Ω")
        try expectRich("1 µF to farad", 0.000001, "F")
        try expectRich("1 mH to H", 0.001, "H")
    },
    EngineCase("rich-nuclear-magnetic-photometric") {
        try expectRich("1 Ci to Bq", 37000000000, "Bq")
        try expectRich("1 rem to Sv", 0.001, "Sv")
        try expectRich("1 Gy to rads", 100, "rad (dose)")
        try expectRich("1 gauss to T", 0.0001, "T")
        try expectRich("1 fc to lx", 10.76391041670972, "lx")
    },

    // MARK: Data (case-sensitive) + rates

    EngineCase("rich-data") {
        try expectRich("1 B to bit", 8, "bit")
        try expectRich("1 KB to B", 1000, "B")
        try expectRich("1 KiB to B", 1024, "B")
        try expectRich("1 kbit/s to bit/s", 1000, "bit/s")
        try expectRich("1 B/s to bit/s", 8, "bit/s")
        try expectRich("10 B/s to kbit/s", 0.08, "kbit/s")
        try expectRichError("5 bit to rad")
    },

    // MARK: Fuel economy (reciprocal-safe)

    EngineCase("rich-fuel-economy") {
        try expectRich("10 km/L to US mpg", 23.521458333333332, "US mpg")
        try expectRich("5 L/100km to L/km", 0.05, "L/km")
        try expectRich("10 km/L to L/km", 0.1, "L/km")
                try expectRich("1 US mpg to km/L", 0.425143707430272, "km/L")
        try expectRich("1 km/L to L/100km", 100, "L/100km")
    },

    // MARK: Currency

    EngineCase("rich-currency-jpy") {
        let rates = Rates(base: "USD", rates: ["USD": 1, "EUR": 1.1, "JPY": 157.98])
        try expectRich("10 EUR to JPY", 10 * 157.98 / 1.1, "JPY", rates: rates)
        try expectRich("100 JPY to EUR", 100 * 1.1 / 157.98, "EUR", rates: rates)
    },
    EngineCase("rich-currency-cross-unknown-code") {
        let rates = Rates(base: "USD", rates: ["USD": 1, "EUR": 1.1])
        try expectRichError("10 GBP to EUR")
        guard let r = richEval("10 GBP to EUR", rates: rates),
              case .error(let msg) = r else {
            throw CaseFailure(message: "missing code must error",
                              location: "RichConversionCases")
        }
        try expectEqual(msg, "Rates unavailable", "generic message")
    },

    // MARK: Number forms

    EngineCase("rich-number-forms") {
        try expectRich("1e3 km to m", 1000000, "m")
        try expectRich("1,000,000 m to km", 1000, "km")
        try expectRich("-5 C to F", 23, "F°")
                // Multiple `to` words are not a conversion: the line falls back
        // to expression evaluation exactly like the legacy engine.
        guard let mm = richEval("5 m to m to m"), case .number(let mmv, _) = mm else {
            throw CaseFailure(message: "5 m to m to m must evaluate as expression",
                              location: "RichConversionCases")
        }
        try expectClose(mmv, 5_000_000, 0, "expression fallback")
    },

    // MARK: Shape guards

    EngineCase("rich-spaced-operators") {
        // Canonical spacing around the slash must not break resolution.
        try expectRich("1 km / L to L / 100km", 100, "L/100km")
        try expectRich("5 km / h to m / s", 1.3888888888888888, "m/s")
        try expectRich("1 N / m to N / m", 1, "N/m")
    },

    EngineCase("rich-not-conversions") {
        // Compact suffixes stay magnitudes.
        guard let a = richEval("5m"), case .number(let va, _) = a else {
            throw CaseFailure(message: "5m must evaluate", location: "RichConversionCases")
        }
        try expectClose(va, 5_000_000, 0, "5m = 5e6")
        guard let b = richEval("2.5k"), case .number(let vb, _) = b else {
            throw CaseFailure(message: "2.5k must evaluate", location: "RichConversionCases")
        }
        try expectClose(vb, 2500, 0, "2.5k = 2500")
        try expectRichError("5 usd to m")
        try expectRichError("5 m to usd")
    },
]
