import Foundation
import NumlexCore

/// r32: expanded currencies, unified marker grammar, everyday and
/// engineering units, and fuel crossing (economy factors m/L,
/// consumption factors L/m — 1 US mpg = exactly 100 US gal/100mi).

private let M = "\u{FFFC}"

private func evalR32(_ line: String,
                     rates: Rates = Rates()) -> LineResult? {
    var v: [String: Double] = [:]
    return evalLine(line, variables: &v, rates: rates, decimalPlaces: 7)
}

private func expectConv(_ line: String, _ value: Double, _ unit: String,
                        rates: Rates = Rates(),
                        tolerance: Double = 0.0001) throws {
    guard let r = evalR32(line, rates: rates) else {
        throw CaseFailure(message: "line must evaluate: \(line)",
                          location: "R32Cases")
    }
    guard case .number(let v, let u) = r else {
        throw CaseFailure(message: "\(line) must be a conversion, got \(r)",
                          location: "R32Cases")
    }
    try expectClose(v, value, tolerance, "\(line) value")
    try expectEqual(u ?? "<none>", unit, "\(line) unit")
}

private func expectConvError(_ line: String) throws {
    let r = evalR32(line)
    guard case .error = r else {
        throw CaseFailure(message: "\(line) must be a generic error, got \(String(describing: r))",
                          location: "R32Cases")
    }
}

private func expectMoney(_ line: String, _ value: Double, _ code: String) throws {
    guard let r = evalR32(line) else {
        throw CaseFailure(message: "line must evaluate: \(line)",
                          location: "R32Cases")
    }
    guard case .money(let v, let c) = r else {
        throw CaseFailure(message: "\(line) must be money, got \(r)",
                          location: "R32Cases")
    }
    try expectClose(v, value, 1e-9, "\(line) value")
    try expectEqual(c, code, "\(line) code")
}

private func expectNotMoney(_ line: String) throws {
    guard let r = evalR32(line) else { return }  // nil or non-money: fine
    if case .money = r {
        throw CaseFailure(message: "\(line) must NOT be money, got \(r)",
                          location: "R32Cases")
    }
}

private func expectFmt(_ value: Double, _ code: String, _ display: String) throws {
    try expectEqual(formatMoney(value, code: code), display,
                    "\(code) \(value)")
}

public let r32Cases: [EngineCase] = [
    // MARK: Currency markers — prefix

    EngineCase("r32-marker-prefix-letters") {
        try expectMoney("Rp25000", 25000, "IDR")
        try expectMoney("zł100", 100, "PLN")
        try expectMoney("Kč100", 100, "CZK")
        try expectMoney("RM50", 50, "MYR")
    },

    EngineCase("r32-marker-prefix-symbols") {
        try expectMoney("CN¥500", 500, "CNY")
        try expectMoney("₩500", 500, "KRW")
        try expectMoney("₹200", 200, "INR")
        try expectMoney("₺100", 100, "TRY")
        try expectMoney("₴80", 80, "UAH")
        try expectMoney("₫1000", 1000, "VND")
        try expectMoney("₱100", 100, "PHP")
        try expectMoney("฿100", 100, "THB")
        try expectMoney("₪50", 50, "ILS")
        try expectMoney("₦100", 100, "NGN")
        try expectMoney("₾10", 10, "GEL")
        try expectMoney("₸100", 100, "KZT")
        try expectMoney("₮1000", 1000, "MNT")
        try expectMoney("៛100", 100, "KHR")
        try expectMoney("₡100", 100, "CRC")
        try expectMoney("₵50", 50, "GHS")
        try expectMoney("₲10000", 10000, "PYG")
        try expectMoney("₯1000", 1000, "LAK")
    },

    EngineCase("r32-marker-prefix-dollars-disambiguated") {
        // Bare `$` stays USD; letter-prefixed dollars keep their codes.
        try expectMoney("$45", 45, "USD")
        try expectMoney("CA$100", 100, "CAD")
        try expectMoney("NZ$50", 50, "NZD")
        try expectMoney("HK$100", 100, "HKD")
        try expectMoney("MX$100", 100, "MXN")
        try expectMoney("NT$100", 100, "TWD")
        try expectMoney("A$50", 50, "AUD")
        try expectMoney("S$100", 100, "SGD")
        try expectMoney("R$100", 100, "BRL")
        try expectMoney("¥500", 500, "JPY")
        try expectMoney("€60", 60, "EUR")
        try expectMoney("£40", 40, "GBP")
    },

    // MARK: Currency markers — postfix

    EngineCase("r32-marker-postfix") {
        try expectMoney("240$", 240, "USD")
        try expectMoney("2.5K$", 2500, "USD")
        try expectMoney("100zł", 100, "PLN")
        try expectMoney("2kRp", 2000, "IDR")
        try expectMoney("3mRM", 3_000_000, "MYR")
    },

    // MARK: Currency markers — negatives (never a marker)

    EngineCase("r32-marker-negatives") {
        try expectNotMoney("$$45")
        try expectNotMoney("Rp")
        try expectNotMoney("the Rp rate")
        try expectNotMoney("100Rpm")
        try expectNotMoney("45$5")
    },

    // MARK: Currency name aliases (unit grammar, live rates)

    EngineCase("r32-alias-name-conversions") {
        let rates = Rates(base: "USD", rates: [
            "USD": 1, "EUR": 1.1, "GBP": 0.8, "INR": 90, "PLN": 4.0,
            "CZK": 25, "IDR": 16000, "CNY": 7.2, "KRW": 1400, "TRY": 40,
            "UAH": 41, "VND": 25400, "BRL": 5.4, "MXN": 18, "TWD": 32,
            "NZD": 1.65, "AUD": 1.5, "SGD": 1.35, "HKD": 7.8, "JPY": 150,
            "ZAR": 19, "AED": 3.6725, "SAR": 3.75, "KWD": 0.306,
            "BHD": 0.376, "JOD": 0.709, "ILS": 5.3, "NGN": 1600,
            "KES": 129, "GHS": 15.6, "THB": 37, "PHP": 58, "MYR": 4.7,
            "KZT": 500, "GEL": 3.05, "CLP": 940, "COP": 4200, "ARS": 1200,
            "PEN": 3.75, "HUF": 410, "RON": 4.97, "BGN": 1.956,
        ])
        try expectConv("10 rupees in USD", 10.0 / 90, "USD", rates: rates)
        try expectConv("10 Indian rupees to USD", 10.0 / 90, "USD", rates: rates)
        try expectConv("100 zloty to euros", 100.0 / 4.0 * 1.1, "EUR", rates: rates)
        try expectConv("5 ringgit in USD", 5.0 / 4.7, "USD", rates: rates)
        try expectConv("2 rand in USD", 2.0 / 19, "USD", rates: rates)
        try expectConv("100 dong in USD", 100.0 / 25400, "USD", rates: rates)
        try expectConv("3 baht to USD", 3.0 / 37, "USD", rates: rates)
        try expectConv("1 shekel in USD", 1.0 / 5.3, "USD", rates: rates)
        try expectConv("20 dirhams to USD", 20.0 / 3.6725, "USD", rates: rates)
        try expectConv("10 liras to USD", 10.0 / 40, "USD", rates: rates)
        try expectConv("5 euros to dollars", 5.0 / 1.1, "USD", rates: rates)
        // Bare `dollar` is deliberately the US dollar only.
        try expectConv("10 dollars to euros", 10.0 * 1.1, "EUR", rates: rates)
        try expectConv("100 yen to dollars", 100.0 / 150, "USD", rates: rates)
        try expectConv("50 won to USD", 50.0 / 1400, "USD", rates: rates)
        try expectConv("1 hryvnia in USD", 1.0 / 41, "USD", rates: rates)
        try expectConv("100 forints to EUR", 100.0 / 410 * 1.1, "EUR", rates: rates)
        // A bare `pound` remains the MASS pound — never a currency.
        try expectConvError("5 pounds in euros")
    },

    // MARK: Currency output (safe symbols + comprehensive minor digits)

    EngineCase("r32-output-symbols") {
        try expectFmt(25000, "IDR", "Rp25,000.00")
        try expectFmt(100, "PLN", "zł100.00")
        try expectFmt(500, "KRW", "₩500")
        try expectFmt(200, "INR", "₹200.00")
        try expectFmt(1000, "VND", "₫1,000")
        try expectFmt(10, "GEL", "₾10.00")
        try expectFmt(600, "CHF", "600.00 CHF")  // no symbol: fallback
        try expectFmt(50, "EUR", "€50.00")
        try expectFmt(45, "USD", "$45.00")
    },

    EngineCase("r32-minor-digits-table") {
        for code in ["BIF", "CLP", "DJF", "GNF", "ISK", "JPY", "KMF",
                     "KRW", "PYG", "RWF", "UGX", "VND", "VUV", "XAF",
                     "XOF", "XPF"] {
            try expectEqual(CurrencyPresentation.minorDigits(for: code), 0,
                            "\(code) has 0 minor digits")
        }
        for code in ["BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND"] {
            try expectEqual(CurrencyPresentation.minorDigits(for: code), 3,
                            "\(code) has 3 minor digits")
        }
        try expectEqual(CurrencyPresentation.minorDigits(for: "CLF"), 4,
                        "CLF has 4 minor digits")
        try expectEqual(CurrencyPresentation.minorDigits(for: "USD"), 2,
                        "default is 2")
        try expectFmt(10, "BHD", "10.000 BHD")
        try expectFmt(1, "CLF", "1.0000 CLF")
    },

    // MARK: Token path (shared marker metadata in TokenExpr)

    EngineCase("r32-token-currency-marker") {
        // "5000\n2.5K$ × <M>": the U+FFFC marker sits at absolute
        // UTF-16 offset 13.
        let u0 = UUID(), u1 = UUID()
        let content = "5000\n2.5K$ × " + M
        let (lines, tokens) = resolveSheet(content: content, lineIDs: [u0, u1],
                                           references: [AnswerReference(sourceLineID: u0,
                                                                        labelLine: 1,
                                                                        location: 13)],
                                           rates: Rates(), decimalPlaces: 7)
        // The token expression returns the money quantity as a number
        // carrying the ISO currency unit (the token live path).
        guard case .number(let v, let unit) = lines[1].result else {
            throw CaseFailure(message: "token money line, got \(lines[1].result)",
                              location: "R32Cases")
        }
        try expectClose(v, 12_500_000, 1e-6, "2.5K$ × 5000")
        try expectEqual(unit ?? "<none>", "USD", "compact postfix marker code")
        if case .active = tokens.last?.state {
            try expect(true, "token stayed live")
        } else {
            throw CaseFailure(message: "token broken: \(String(describing: tokens.last?.state))",
                              location: "R32Cases")
        }
    },

    // MARK: Everyday units

    EngineCase("r32-everyday-length") {
        try expectConv("1 hand to in", 4, "in")
        try expectConv("1 furlong to m", 201.168, "m")
        try expectConv("1 chain to m", 20.1168, "m")
        try expectConv("1 rod to m", 5.0292, "m")
        try expectConv("1 fathom to m", 1.8288, "m")
        try expectConv("1 angstrom to nm", 0.1, "nm")
        try expectConv("1 micron to m", 1e-6, "m", tolerance: 1e-12)
        try expectConv("1 US ft to m", 1200.0 / 3937.0, "m", tolerance: 1e-9)
        try expectConv("1 pica to pt (type)", 12, "pt (type)")
    },

    EngineCase("r32-everyday-area-volume") {
        try expectConv("1 are to m2", 100, "m²")
        try expectConv("1 rood to acres", 0.25, "acre")
        try expectConv("1 section to acres", 640, "acre")
        try expectConv("1 barn to m2", 1e-28, "m²", tolerance: 1e-34)
        try expectConv("1 metric cup to ml", 250, "ml")
        try expectConv("1 metric tablespoon to ml", 15, "ml")
        try expectConv("1 US fl dr to ml", 3.6966911953125, "ml")
        try expectConv("1 bbl to gal", 42, "gal")
        try expectConv("1 bushel to L", 35.23907016688, "L")
        try expectConv("1 peck to bushel", 0.25, "bushel")
    },

    EngineCase("r32-everyday-mass-time-speed") {
        try expectConv("1 slug to kg", 14.59390293720636, "kg")
        try expectConv("1 Da to g", 1.66053906660e-24, "g", tolerance: 1e-30)
        try expectConv("1 quintal to kg", 100, "kg")
        try expectConv("1 cwt (US) to lb", 100, "lb")
        try expectConv("1 cwt (UK) to lb", 112, "lb")
        try expectConv("1 troy ounce to g", 31.1034768, "g")
        try expectConv("1 dwt to g", 1.55517384, "g")
        // The bare `year`/`yr` is the GREGORIAN AVERAGE (365.2425 days);
        // the Julian year stays its own unit.
        try expectConv("1 yr to days", 365.2425, "day")
        try expectConv("1 mo to days", 30.436875, "day")
        try expectConv("1 common year to days", 365, "day")
        try expectConv("1 julian year to days", 365.25, "day")
        try expectConv("1 quarter (time) to days", 91.310625, "day")
        try expectConv("1 c0 to km/h", 299_792_458.0 * 3.6, "km/h")
        try expectConv("1 Mach to m/s", 340.29, "m/s")
    },

    // MARK: Engineering units — pressure, force, torque

    EngineCase("r32-pressure") {
        try expectConv("1 at to kPa", 98.0665, "kPa")
        try expectConv("1 at to bar", 0.980665, "bar")
        try expectConv("1 kgf/cm2 to kPa", 98.0665, "kPa")
        try expectConv("1 mmH2O to Pa", 9.80665, "Pa")
        try expectConv("1 cmH2O to Pa", 98.0665, "Pa")
        try expectConv("1 psf to Pa", 47.88025898033584, "Pa", tolerance: 1e-9)
    },

    EngineCase("r32-force-torque") {
        try expectConv("1 ozf to N", 0.27801385095378125, "N", tolerance: 1e-9)
        try expectConv("1 kip to kN", 4.4482216152605, "kN")
        try expectConv("1 poundal to N", 0.138254954376, "N", tolerance: 1e-9)
        try expectConv("1 us ton-force to N", 8896.443230521, "N")
        try expectConv("1 tonf (t) to N", 9806.65, "N")
        try expectConv("1 N·cm to N·m", 0.01, "N·m")
        try expectConv("1 N·mm to N·m", 0.001, "N·m")
        try expectConv("1 ozf·in to N·m", 0.27801385095378125 * 0.0254, "N·m", tolerance: 1e-9)
    },

    // MARK: Engineering units — energy, power, flow

    EngineCase("r32-energy-power") {
        try expectConv("1 erg to J", 1e-7, "J", tolerance: 1e-13)
        try expectConv("1 t TNT to J", 4.184e9, "J", tolerance: 1.0)
        try expectConv("1 quad to kWh", 1.05505585262e18 / 3.6e6, "kWh", tolerance: 1.0)
        // 1 mechanical hp = 745.6998715822702 W, so 1 hph = 0.745… kWh.
        try expectConv("1 hph to kWh", 0.7456998715822702, "kWh", tolerance: 1e-9)
        try expectConv("1 toe to J", 41.868e9, "J", tolerance: 10.0)
        try expectConv("1 hp (electric) to W", 746, "W")
        try expectConv("1 hp (boiler) to W", 9809.5, "W")
        try expectConv("1 TR to W", 3516.8528420667, "W")
    },

    EngineCase("r32-flow") {
        try expectConv("1 UK gpm to L/s", 0.00454609 / 60.0 / 0.001, "L/s")
        try expectConv("1 cfm to m³/h", 0.028316846592 * 60.0, "m³/h")
        try expectConv("1 US mgd to L/s", 0.003785411784 * 1e6 / 86400.0 / 0.001, "L/s")
        try expectConv("1 bbl/d to L/s", 0.158987294928 / 86400.0 / 0.001, "L/s", tolerance: 1e-9)
    },

    // MARK: Fuel economy (exact by construction on the m/L / L/m base)

    EngineCase("r32-fuel-crossings") {
        try expectConv("1 mi/L to US mpg", 3.785411784, "US mpg")
        try expectConv("1 US mpg to US gal/100mi", 100, "US gal/100mi")
        try expectConv("1 UK mpg to UK gal/100mi", 100, "UK gal/100mi", tolerance: 1e-9)
        try expectConv("1 UK mpg to L/100km", 282.48095238095235, "L/100km")
        // US mpg crossing unchanged by the factor audit.
        try expectConv("1 US mpg to L/100km", 235.21458333333334, "L/100km")
        try expectConv("10 km/L to US mpg", 23.521458333333332, "US mpg")
    },

    // MARK: Viscosity (new dimension kinds, collision-free vectors)

    EngineCase("r32-viscosity") {
        try expectConv("1 cP to Pa·s", 0.001, "Pa·s")
        try expectConv("1 P to Pa·s", 0.1, "Pa·s")
        try expectConv("1 reyn to Pa·s", 6894.757293168, "Pa·s")
        try expectConv("1 St to m²/s", 0.0001, "m²/s")
        try expectConv("1 cSt to m²/s", 1e-6, "m²/s", tolerance: 1e-12)
        try expectConv("1 ft²/s to m²/s", 0.09290304, "m²/s")
    },
]
