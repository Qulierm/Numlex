import Foundation
import NumlexCore

/// Table-driven coverage for the normalized conversion engine: every
/// legacy phrase, the new aliases and reverses, incompatible-dimension
/// and unknown-unit errors, and the boundaries against the magnitude
/// suffixes (`5m`, `2.5k`) and the typed-space policy.

private func evalConv(_ line: String,
                      rates: Rates = Rates()) throws -> LineResult {
    var v: [String: Double] = [:]
    guard let r = evalLine(line, variables: &v, rates: rates, decimalPlaces: 7)
    else {
        throw CaseFailure(message: "line must evaluate: \(line)",
                          location: "ConversionCases")
    }
    return r
}

private func expectConversion(_ line: String, _ value: Double, _ unit: String,
                              rates: Rates = Rates(),
                              tolerance: Double = 0.0001) throws {
    let r = try evalConv(line, rates: rates)
    guard case .number(let v, let u) = r else {
        throw CaseFailure(message: "\(line) must be a conversion, got \(r)",
                          location: "ConversionCases")
    }
    try expectClose(v, value, tolerance, "\(line) value")
    try expectEqual(u ?? "<none>", unit, "\(line) unit")
}

private func expectConversionError(_ line: String,
                                   rates: Rates = Rates()) throws {
    let r = try evalConv(line, rates: rates)
    guard case .error = r else {
        throw CaseFailure(
            message: "\(line) must be a generic error, got \(r) — never a number",
            location: "ConversionCases")
    }
}

public let conversionCases: [EngineCase] = [
    EngineCase("conversion-legacy-phrases") {
        // Every phrase in the legacy phrase map, with its legacy label.
        try expectConversion("10 km to meter", 10_000, "meters")
        try expectConversion("10 meter to km", 0.01, "km")
        try expectConversion("10 mile to km", 16.0934, "km", tolerance: 0.0001)
        try expectConversion("10 km to mile", 10_000 / 1609.34, "miles", tolerance: 0.0001)
        try expectConversion("10 cm to m", 0.1, "m")
        try expectConversion("10 m to cm", 1000, "cm")
        try expectConversion("10 cm to km", 0.0001, "km")
        try expectConversion("10 kg to t", 0.01, "ton")
        try expectConversion("10 t to kg", 10_000, "kg")
        try expectConversion("10 ml to teaspoon", 2, "teaspoons")
        try expectConversion("10 teaspoon to ml", 50, "ml")
        try expectConversion("10 liter to ml", 10_000, "ml")
        try expectConversion("10 ml to liter", 0.01, "L")
        // Temperatures keep their custom transforms and labels.
        try expectConversion("100 C to F", 212, "F°")
        try expectConversion("32 F to C", 0, "C°")
        try expectConversion("273.15 K to C", 0, "C°", tolerance: 0.0001)
        try expectConversion("0 C to K", 273.15, "K°", tolerance: 0.0001)
        // Currencies: the six pairs and the rates-unavailable error.
        let rates = Rates(USD: 90, EUR: 100, EURUSD: 1.1)
        try expectConversion("10 USD to RUB", 900, "RUB", rates: rates)
        try expectConversion("10 EUR to RUB", 1000, "RUB", rates: rates)
        try expectConversion("10 RUB to EUR", 0.1, "EUR", rates: rates)
        try expectConversion("10 USD to EUR", 11, "EUR", rates: rates)
        // Legacy direction: eur->usd divides by the EURUSD rate (kept
        // exactly as before this refactor).
        try expectConversion("10 EUR to USD", 10.0/1.1, "USD", rates: rates, tolerance: 0.0001)
        try expectConversion("10 RUB to USD", 10.0/90, "usd", rates: rates, tolerance: 0.0001)
        try expectConversionError("10 USD to RUB")
    },

    EngineCase("conversion-fixed-factors") {
        // The legacy mg<->kg pair used 1e-3; the correct factor is 1e-6.
        try expectConversion("10 mg to kg", 1e-5, "kg")
        try expectConversion("10 kg to mg", 1e7, "mg")
        // And the canonical target symbol for short targets: the legacy
        // `km to cm` reported `km`; the target symbol is now preferred.
        try expectConversion("10 km to cm", 1_000_000, "cm")
    },

    EngineCase("conversion-alias-matrix") {
        // Length
        try expectConversion("5 km to m", 5000, "m")
        try expectConversion("5 m to cm", 500, "cm")
        try expectConversion("5 mm to cm", 0.5, "cm")
        try expectConversion("5 cm to mm", 50, "mm")
        try expectConversion("5 mi to km", 8.0467, "km", tolerance: 0.0001)
        try expectConversion("5 km to mi", 5000 / 1609.34, "mi", tolerance: 0.0001)
        try expectConversion("5 meters to mm", 5000, "mm")
        // Mass
        try expectConversion("5 mg to g", 0.005, "g")
        try expectConversion("5 g to mg", 5000, "mg")
        try expectConversion("5 g to kg", 0.005, "kg")
        try expectConversion("5 kg to g", 5000, "g")
        try expectConversion("5 t to g", 5_000_000, "g")
        try expectConversion("5 tons to kg", 5000, "kg")
        try expectConversion("5 kilograms to grams", 5000, "g")
        // Volume
        try expectConversion("5 ml to l", 0.005, "L")
        try expectConversion("5 l to ml", 5000, "ml")
        try expectConversion("5 l to tsp", 1000, "tsp")
        try expectConversion("5 tsp to ml", 25, "ml")
        try expectConversion("5 milliliters to liters", 0.005, "L")
    },

    EngineCase("conversion-case-plural-comma-signed") {
        try expectConversion("10 kilometers to meters", 10_000, "meters")
        try expectConversion("10 Kilometers to Meters", 10_000, "meters")
        try expectConversion("10 KM TO M", 10_000, "m")
        try expectConversion("1,000 km to m", 1_000_000, "m")
        try expectConversion("2.5 km to m", 2500, "m")
        try expectConversion("-5 C to F", 23, "F°")
    },

    EngineCase("conversion-incompatible-dimensions-error") {
        // Recognized units, different dimensions: generic error, never
        // the leading number.
        try expectConversionError("5 kg to m")
        try expectConversionError("5 m to kg")
        try expectConversionError("5 l to m")
        try expectConversionError("5 cm to ml")
        try expectConversionError("5 g to ml")
    },

    EngineCase("conversion-unknown-units-error") {
        try expectConversionError("5 parsecs to m")
        try expectConversionError("5 m to parsecs")
        // A currency word in the measurement slot is an unknown unit.
        try expectConversionError("5 usd to m")
    },

    EngineCase("conversion-compact-suffix-still-magnitude") {
        // No whitespace after the number: never a conversion shape.
        let compact = try evalConv("5m")
        guard case .number(let v, nil) = compact else {
            throw CaseFailure(message: "5m must be magnitude, got \(compact)",
                              location: "ConversionCases")
        }
        try expectEqual(v, 5_000_000, "5m value")
        let k = try evalConv("2.5k")
        guard case .number(let vk, nil) = k else {
            throw CaseFailure(message: "2.5k must be magnitude, got \(k)",
                              location: "ConversionCases")
        }
        try expectEqual(vk, 2500, "2.5k value")
    },

    EngineCase("conversion-spaces-stay-preserved") {
        // The canonical document keeps every internal space of a
        // complete conversion byte-for-byte, so typed `5 km to m`
        // survives the format pass.
        try expectEqual(NotebookFormatting.canonicalDocument("5 km to m"),
                        "5 km to m", "km to m kept")
        try expectEqual(NotebookFormatting.canonicalDocument("5 m to cm"),
                        "5 m to cm", "m to cm kept")
        try expectEqual(NotebookFormatting.canonicalDocument("10 kilometers to meters\nx=5"),
                        "10 kilometers to meters\nx = 5",
                        "conversion line untouched, math line canonicalized")
        // And the typed-space policy is still what makes it typeable.
        try expectEqual(EditIntent(replacement: " "), .whitespace, "space intent")
    },

    EngineCase("conversion-syntax-spans") {
        // Alias conversion: number cyan, unit words conversion-colored,
        // `to` carries no span (base white).
        let spans = SyntaxClassifier.spans(for: "5 km to m",
                                           rates: Rates(), decimalPlaces: 7)[0]
        try expectEqual(spans.count, 3, "three spans: number + two units")
        try expectEqual(spans[0].role, .number, "leading number")
        try expectEqual(spans[0].range, NSRange(location: 0, length: 1), "5 range")
        try expectEqual(spans[1].role, .conversion, "from unit")
        try expectEqual(spans[1].range, NSRange(location: 2, length: 2), "km range")
        try expectEqual(spans[2].role, .conversion, "to unit")
        try expectEqual(spans[2].range, NSRange(location: 8, length: 1), "m range")
        let toRange = NSRange(location: 4, length: 2)
        try expect(!spans.contains { $0.range == toRange }, "`to` stays base")
        // An incompatible line is a generic error but keeps the
        // conversion coloring (errorSpans conversion shape).
        let errSpans = SyntaxClassifier.spans(for: "5 kg to m",
                                              rates: Rates(), decimalPlaces: 7)[0]
        try expectEqual(errSpans.map { $0.role },
                        [.number, .conversion, .conversion],
                        "error line keeps unit colors")
        try expect(!errSpans.contains { $0.range == NSRange(location: 4, length: 2) },
                   "error `to` stays base")
    },
]
