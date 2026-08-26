import Foundation
import NumlexCore

/// Data-driven integrity of the unit algebra: no alias or label
/// collisions, every registered linear unit round-trips through the
/// label index, and the representative lookup rules (case-sensitive
/// data units, prefix decomposition, exponents, full-expression
/// aliases, family walls) behave exactly as specified.

private func evalLine1(_ line: String,
                       rates: Rates = Rates()) -> LineResult? {
    var vars: [String: Double] = [:]
    return evalLine(line, variables: &vars, rates: rates, decimalPlaces: 7)
}

public let unitCatalogCases: [EngineCase] = [
    EngineCase("catalog-no-alias-collisions") {
        let collisions = UnitCatalog.aliasCollisions()
        try expect(collisions.isEmpty,
                   "alias collisions: \(collisions) — no two units share an input alias")
    },
    EngineCase("catalog-no-label-collisions") {
        let collisions = UnitCatalog.labelCollisions()
        try expect(collisions.isEmpty,
                   "label collisions: \(collisions) — two units must not share a label")
    },
    EngineCase("catalog-size-and-currency-coverage") {
        try expect(UnitCatalog.unitCount >= 220,
                   "only \(UnitCatalog.unitCount) units — catalog is broad")
        try expectEqual(FiatCurrencies.codes.count, 166, "fiat code count")
        for code in ["USD", "EUR", "RUB", "JPY", "GBP", "CNY"] {
            try expect(FiatCurrencies.codes.contains(code), "missing \(code) — code bundled")
        }
        for bad in ["BTC", "ETH", "XAU", "XAG", "XPT"] {
            try expect(!FiatCurrencies.codes.contains(bad),
                       "\(bad) must be excluded — fiat only")
        }
    },
    EngineCase("catalog-every-linear-unit-round-trips") {
        for u in UnitCatalog.all {
            switch u.kind {
            case .factor(let v, let f):
                try expect(f.isFinite && f > 0,
                           "\(u.id) factor \(f) illegal", "finite positive factor")
                guard let e = UnitCatalog.resolveLabel(u.label) else {
                    throw CaseFailure(message: "label \(u.label) does not resolve",
                                      location: "UnitCatalogCases")
                }
                try expect(e.vector == v,
                           "\(u.label) vector \(e.vector) != \(v)", "label keeps vector")
                try expect(e.family == u.family,
                           "\(u.label) family changed", "label keeps family")
                try expectClose(e.toBase, f, max(f * 1e-9, 1e-300),
                                "\(u.label) factor drifted")
                // Identity conversion is exact.
                guard let id = convertValue(2.5, from: e, to: e, rates: Rates()) else {
                    throw CaseFailure(message: "\(u.label) identity failed",
                                      location: "UnitCatalogCases")
                }
                try expectClose(id.value, 2.5, 0, "\(u.label) identity value")
                try expectEqual(id.unit, u.label, "\(u.label) identity label")
            case .temperature, .currency, .fuel:
                // Specials: the label must resolve back to the same kind.
                guard let e = UnitCatalog.resolveLabel(u.label) else {
                    throw CaseFailure(message: "label \(u.label) does not resolve",
                                      location: "UnitCatalogCases")
                }
                try expect(e.kind == u.kind,
                           "\(u.label) kind \(e.kind) != \(u.kind) — special label kind")
            }
        }
    },
    EngineCase("catalog-data-units-are-case-sensitive") {
        // MB (bytes) and Mb (bits) coexist; the lowercase ambiguous fold
        // `mb` stays unknown rather than guessing.
        guard let mb = UnitCatalog.resolveToken("MB"),
              let mbt = UnitCatalog.resolveToken("Mb") else {
            throw CaseFailure(message: "MB/Mb must resolve", location: "UnitCatalogCases")
        }
        try expectClose(mb.linearFactor!, 8e6, 0, "MB = 8e6 bits (bytes)")
        try expectClose(mbt.linearFactor!, 1e6, 0, "Mb = 1e6 bits (bits)")
        try expect(UnitCatalog.resolveToken("mb") == nil,
                   "mb must stay unknown (ambiguous fold) — mb deterministic")
        try expect(UnitCatalog.resolveToken("kB") != nil, "kB = kilobyte", "kB")
        try expect(UnitCatalog.resolveToken("kb") != nil, "kb = kilobit", "kb")
        guard let gb = UnitCatalog.resolveToken("GB"),
              let gbit = UnitCatalog.resolveToken("Gb") else {
            throw CaseFailure(message: "GB/Gb must resolve", location: "UnitCatalogCases")
        }
        try expectClose(gb.linearFactor!, 8e9, 0, "GB = 8e9 bits")
        try expectClose(gbit.linearFactor!, 1e9, 0, "Gb = 1e9 bits")
    },
    EngineCase("catalog-prefix-decomposition") {
        try expectClose(UnitCatalog.resolveToken("nm")?.linearFactor ?? -1, 1e-9, 0, "nm = nanometer")
        try expectClose(UnitCatalog.resolveToken("pm")?.linearFactor ?? -1, 1e-12, 0, "pm = picometer")
        try expectClose(UnitCatalog.resolveToken("mm")?.linearFactor ?? -1, 1e-3, 0, "mm = millimeter")
        try expectClose(UnitCatalog.resolveToken("mg")?.linearFactor ?? -1, 1e-6, 0, "mg = milligram")
        try expectClose(UnitCatalog.resolveToken("ms")?.linearFactor ?? -1, 1e-3, 0, "ms = millisecond")
        try expectClose(UnitCatalog.resolveToken("mA")?.linearFactor ?? -1, 1e-3, 0, "mA = milliampere")
        try expectClose(UnitCatalog.resolveToken("kV")?.linearFactor ?? -1, 1e3, 0, "kV = kilovolt")
        try expectClose(UnitCatalog.resolveToken("kΩ")?.linearFactor ?? -1, 1e3, 0, "kΩ = kiloohm")
        try expect(UnitCatalog.resolveToken("mWb") != nil, "mWb resolves", "mWb")
        try expect(UnitCatalog.resolveToken("dB") == nil,
                   "dB is a decibel, never a unit — dB denied")
        try expect(UnitCatalog.resolveToken("d") == nil,
                   "bare d is not a unit — no bare d")
    },
    EngineCase("catalog-exponents") {
        guard let m2 = UnitCatalog.resolveToken("m2") else {
            throw CaseFailure(message: "m2 must resolve", location: "UnitCatalogCases")
        }
        try expectClose(m2.linearFactor!, 1.0, 0, "m2 = 1 m²")
        try expectEqual(m2.label, "m²", "m2 label")
        guard let cm3 = UnitCatalog.resolveToken("cm3") else {
            throw CaseFailure(message: "cm3 must resolve", location: "UnitCatalogCases")
        }
        try expectClose(cm3.linearFactor!, 1e-6, 1e-21, "cm3 = 1e-6 m³")
        guard let ft2 = UnitCatalog.resolveToken("ft²") else {
            throw CaseFailure(message: "ft² must resolve", location: "UnitCatalogCases")
        }
        try expectClose(ft2.linearFactor!, 0.09290304, 0, "ft² exact")
    },
    EngineCase("catalog-full-expression-aliases") {
        func factor(_ input: String) -> Double? {
            UnitCatalog.resolveExpression(input)?.unit.toBase
        }
        func kind(_ input: String) -> UnitKind? {
            UnitCatalog.resolveExpression(input)?.unit.kind
        }
        try expectClose(factor("nautical mile") ?? -1, 1852, 0, "nautical mile")
        try expectClose(factor("nautical miles") ?? -1, 1852, 0, "nautical miles (plural)")
        try expectClose(factor("in.") ?? -1, 0.0254, 0, "trailing dot inch")
        try expectClose(factor("imperial gallon") ?? -1, 0.00454609, 0, "imperial gallon")
        try expectClose(factor("N m") ?? -1, 1.0, 0, "N m = N·m")
        try expectClose(factor("N·m") ?? -1, 1.0, 0, "N·m")
        try expectClose(factor("ft·lbf") ?? -1, 1.3558179483314004, 1e-12, "ft·lbf energy")
        try expectClose(factor("lbf·ft") ?? -1, 1.3558179483314004, 1e-12, "lbf·ft torque")
        func isFuel(_ input: String) -> Bool {
            guard let k = kind(input) else { return false }
            if case .fuel = k { return true }
            return false
        }
        try expect(isFuel("L/100km"), "L/100km is fuel", "fuel")
        try expect(isFuel("l/100km"), "l/100km is fuel", "fuel")
        try expect(isFuel("US mpg"), "US mpg is fuel", "fuel")
        try expect(isFuel("UK mpg"), "UK mpg is fuel", "fuel")
        // Energy vs torque: SAME value, DIFFERENT family wall.
        let energy = UnitCatalog.resolveExpression("ft·lbf")!.unit
        let torque = UnitCatalog.resolveExpression("lbf·ft")!.unit
        try expect(energy.family == .energy && torque.family == .torque,
                   "families differ", "family wall")
    },
    EngineCase("catalog-family-walls") {
        func kind(_ label: String) -> UnitExpr? { UnitCatalog.resolveLabel(label) }
        try expect(kind("J") != nil && kind("N·m") != nil, "energy/torque labels", "both")
        // Energy never converts to torque (same vector, different family).
        try expect(convertValue(5, from: kind("J")!, to: kind("N·m")!,
                                rates: Rates()) == nil, "J -> N·m blocked", "wall")
        try expect(convertValue(5, from: kind("N·m")!, to: kind("J")!,
                                rates: Rates()) == nil, "N·m -> J blocked", "wall")
        // Dimensionless walls.
        try expect(convertValue(5, from: kind("rad")!, to: kind("bit")!,
                                rates: Rates()) == nil, "rad -> bit blocked", "wall")
        try expect(convertValue(5, from: kind("Hz")!, to: kind("Bq")!,
                                rates: Rates()) == nil, "Hz -> Bq blocked", "wall")
        try expect(convertValue(5, from: kind("Bq")!, to: kind("rpm")!,
                                rates: Rates()) == nil, "Bq -> rpm blocked", "wall")
        try expect(convertValue(5, from: kind("Gy")!, to: kind("W")!,
                                rates: Rates()) == nil, "Gy -> W blocked", "wall")
        try expect(convertValue(5, from: kind("cd")!, to: kind("lm")!,
                                rates: Rates()) == nil, "cd -> lm blocked", "wall")
        // Fuel: economy and consumption forms never mix.
        // Crossing economy and consumption is the true reciprocal.
        try expectClose(convertValue(10, from: kind("km/L")!, to: kind("L/km")!,
                                     rates: Rates())?.value ?? -1, 0.1, 1e-12,
                        "10 km/L = 0.1 L/km")
        // Temperature is affine, not a factor: same family only.
        try expect(convertValue(5, from: kind("C°")!, to: kind("F°")!,
                                rates: Rates()) != nil, "C -> F works — affine")
        try expect(convertValue(5, from: kind("C°")!, to: kind("m")!,
                                rates: Rates()) == nil, "C -> m blocked — wall")
    },
    EngineCase("catalog-normalization") {
        try expectEqual(UnitCatalog.normalize("  N·m  "), "N*m", "middle dot")
        try expectEqual(UnitCatalog.normalize("N×m"), "N*m", "times sign")
        try expectEqual(UnitCatalog.normalize("µm"), "µm", "micro sign 1")
        try expectEqual(UnitCatalog.normalize("\u{03BC}m"), "µm", "greek micro unifies")
        try expectEqual(UnitCatalog.normalize("ft²"), "ft^2", "superscript two")
        try expectEqual(UnitCatalog.normalize("in."), "in", "trailing dot")
        try expectEqual(UnitCatalog.normalize("L / 100 km"), "L/100 km", "slash spaces tighten")
    },
]
