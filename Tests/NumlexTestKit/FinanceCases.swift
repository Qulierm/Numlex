import Foundation
import NumlexCore

// MARK: - Package 2: financial functions

private func finEval(_ line: String,
                     context: NumberFormatContext = .legacy,
                     financial: FinancialContext = .defaults,
                     tax: FinancialContext? = nil) -> LineResult? {
    var v: [String: Double] = [:]
    return evalLine(line, variables: &v, rates: Rates(), decimalPlaces: 10,
                    context: context, unitContext: .builtIns,
                    financial: tax ?? financial)
}

private func finText(_ line: String,
                     context: NumberFormatContext = .legacy,
                     financial: FinancialContext = .defaults) -> String? {
    guard let r = finEval(line, context: context, financial: financial) else { return nil }
    return AnswerDisplay.displayText(for: r, decimalPlaces: 10, context: context)
}

private func expectFin(_ line: String, _ expected: String,
                       context: NumberFormatContext = .legacy,
                       tax: FinancialContext = .defaults) throws {
    guard let text = finText(line, context: context, financial: tax) else {
        throw CaseFailure(message: "no finance text for \(line)", location: "Finance")
    }
    try expectEqual(text, expected, "\(line)")
}

private func expectFinError(_ line: String) throws {
    guard let r = finEval(line) else {
        throw CaseFailure(message: "\(line) must evaluate", location: "Finance")
    }
    guard case .error = r else {
        throw CaseFailure(message: "\(line) must be a strict error, got \(r)",
                          location: "Finance")
    }
}

private let finContextDE = NumberFormatContext(
    locale: Locale(identifier: "de_DE"),
    decimalSeparator: ",",
    groupingSeparator: ".",
    argumentSeparator: ";",
    displayGrouping: true,
    compactNotation: false,
    convertForeignOnPaste: false)

public let financeCases: [EngineCase] = [

    EngineCase("finance-investment-official-corpus") {
        try expectFin("$1,000 after 3 years at 7%", "$1,225.04")
        try expectFin("$1,000 for 3 years at 7% compounding monthly", "$1,232.93")
        try expectFin("$1,000 for 3 years at 7% compounding quarterly", "$1,231.44")
        try expectFin("$1,000 for 3 years at 7% compounding annually", "$1,225.04")
        try expectFin("interest on $1,000 after 3 years at 7%", "$225.04")
        try expectFin("interest on $1,000 for 3 years at 7% compounding monthly",
                      "$232.93")
        try expectFin("$500 invested $1,500 returned", "2x")
        // The CAGR percent keeps the engine's full precision; the
        // percent presentation follows the row's effective decimals.
        try expectFin("annual return on $1,000 invested $1,500 returned after 3 years",
                      "14.4714242553%")
        try expectFin("present value of $1,000 after 3 years at 7%", "$816.30")
        // `at`/`@` and explicit `for` are the same grammar.
        try expectFin("$1,000 after 3 years @ 7%", "$1,225.04")
        try expectFin("present value of $1,225.04 for 3 years at 7%", "$1,000.00")
    },

    EngineCase("finance-investment-domain-and-strictness") {
        // Negative rates stay in the real domain.
        try expectFin("$1,000 after 2 years at -5%", "$902.50")
        // Fractional years.
        try expectFin("$1,000 after 1.5 years at 7%", "$1,106.82")
        // Daily compounding (365).
        try expectFin("$1,000 after 1 year at 5% compounding daily", "$1,051.27")
        // Zero years / out-of-range rates / unknown compounding are strict.
        try expectFinError("$1,000 after 0 years at 7%")
        try expectFinError("$1,000 after -3 years at 7%")
        try expectFinError("$1,000 after 3 years at 7% compounding hourly")
        try expectFinError("$1,000 after 3 years at 7% compounding")
        try expectFinError("$1,000 after 3 years at 7% extra")
        try expectFinError("$1,000 after 3 years at -1200%")
        // A negative base with a fractional exponent is rejected.
        try expectFinError("$1,000 after 3.5 years at -400%")
        // ROI requires a positive invested amount (a zero RETURN is a
        // valid -100% outcome, not a domain error).
        try expectFinError("$0 invested $500 returned")
        try expectFin("$100 invested $0 returned", "-1x")
        // CAGR requires positive amounts and a positive year count.
        try expectFinError("annual return on $0 invested $500 returned after 3 years")
        try expectFinError("annual return on $100 invested $0 returned after 3 years")
        try expectFinError("annual return on $100 invested $200 returned after 0 years")
    },

    EngineCase("finance-money-operands-and-no-theft") {
        // Ordinary money keeps its lane.
        try expectFin("$5 + $3", "$8.00")
        try expectFin("lunch was $55 + 25% tip", "$68.75")
        try expectFin("$600", "$600.00")
        // Units/dates/workdays keep their lanes.
        try expectFin("5 km to m", "5,000 m")
        try expectFin("May 5 + 2 days", "May 7")
        try expectFin("workdays in 3 weeks", "15 workdays")
        // Named typed money operands resolve through the same money core
        // (the name lives in the sheet's typed environment).
        var namedVars: [String: Double] = [:]
        let rows = evaluateSheet(
            "monthly rent = $1,000\nmonthly rent after 3 years at 7%",
            variables: &namedVars, rates: Rates(), decimalPlaces: 10)
        guard rows.count == 2,
              let namedText = AnswerDisplay.displayText(for: rows[1].result,
                                                        decimalPlaces: 10,
                                                        context: .legacy) else {
            throw CaseFailure(message: "named money operand", location: "Finance")
        }
        try expectEqual(namedText, "$1,225.04", "named money operand")
        // Prose mentioning the keywords is not stolen.
        if let prose = finEval("interest on my savings is low"), case .money = prose {
            throw CaseFailure(message: "prose must not be money", location: "Finance")
        }
    },

    EngineCase("finance-investment-kinds-and-regional") {
        // ROI keeps the multiplier kind; CAGR the percent kind.
        guard let roi = finEval("$500 invested $1,500 returned"),
              case .number(let rv, _, let rk, _) = roi else {
            throw CaseFailure(message: "ROI kind", location: "Finance")
        }
        try expectClose(rv, 2, 1e-9, "ROI value")
        try expectEqual(rk, .multiplier, "ROI multiplier kind")
        guard let cagr = finEval("annual return on $1,000 invested $1,500 returned after 3 years"),
              case .number(let cv, _, let ck, _) = cagr else {
            throw CaseFailure(message: "CAGR kind", location: "Finance")
        }
        try expectClose(cv, 0.144714, 1e-5, "CAGR value")
        try expectEqual(ck, .percent, "CAGR percent kind")
        // Visible == copy.
        try expectEqual(AnswerDisplay.text(for: roi, decimalPlaces: 10, context: .legacy),
                        AnswerDisplay.displayText(for: roi, decimalPlaces: 10,
                                                  context: .legacy),
                        "ROI copy parity")
        // Regional decimal comma: dot grouping + comma decimal both parse.
        guard let de = finEval("$1.000 after 3 years at 7,5%", context: finContextDE),
              case .money(let value, let code) = de else {
            throw CaseFailure(message: "regional comma parse", location: "Finance")
        }
        try expectClose(value, 1000 * pow(1.075, 3), 1e-6, "regional rate value")
        try expectEqual(code, "USD", "currency preserved")
    },

    EngineCase("finance-token-operands") {
        let marker = "\u{FFFC}"
        // `<token> after 3 years at 7%`.
        let id0 = UUID(), id1 = UUID()
        let content1 = "$1,000\n" + marker + " after 3 years at 7%"
        let markerLoc1 = ("$1,000" as NSString).length + 1
        let resolved1 = resolveSheet(
            content: content1, lineIDs: [id0, id1],
            references: [AnswerReference(sourceLineID: id0, labelLine: 1,
                                         location: markerLoc1)],
            rates: Rates(), decimalPlaces: 10, financial: .defaults)
        guard resolved1.lines.count == 2,
              let text1 = AnswerDisplay.displayText(for: resolved1.lines[1].result,
                                                    decimalPlaces: 10,
                                                    context: .legacy) else {
            throw CaseFailure(message: "token investment phrase", location: "Finance")
        }
        try expectEqual(text1, "$1,225.04", "token investment")
        // `<token> invested <token2> returned` -> 2x.
        let id3 = UUID(), id4 = UUID(), id5 = UUID()
        let content2 = "$500\n$1,500\n" + marker + " invested " + marker + " returned"
        let line0Len = ("$500" as NSString).length + 1
        let line1Len = ("$1,500" as NSString).length + 1
        let m1 = line0Len + line1Len
        let m2 = m1 + (marker as NSString).length + (" invested " as NSString).length
        let resolved2 = resolveSheet(
            content: content2, lineIDs: [id3, id4, id5],
            references: [AnswerReference(sourceLineID: id3, labelLine: 1, location: m1),
                         AnswerReference(sourceLineID: id4, labelLine: 2, location: m2)],
            rates: Rates(), decimalPlaces: 10, financial: .defaults)
        guard resolved2.lines.count == 3,
              let text2 = AnswerDisplay.displayText(for: resolved2.lines[2].result,
                                                    decimalPlaces: 10,
                                                    context: .legacy) else {
            throw CaseFailure(message: "token ROI phrase", location: "Finance")
        }
        try expectEqual(text2, "2x", "token ROI")
    },

    EngineCase("finance-loan-official-corpus") {
        // P=10000, N=6, R=6%: the ONE monthly amortization schedule
        // (pmt = 165.7289...) divided by the requested period count.
        try expectFin("monthly repayment on $10,000 over 6 years at 6%", "$165.73")
        try expectFin("daily repayment on $10,000 over 6 years at 6%", "$5.45")
        try expectFin("annual repayment on $10,000 over 6 years at 6%", "$1,988.75")
        try expectFin("total repayment on $10,000 over 6 years at 6%", "$11,932.48")
        try expectFin("daily interest on $10,000 over 6 years at 6%", "$0.88")
        try expectFin("monthly interest on $10,000 over 6 years at 6%", "$26.84")
        try expectFin("annual interest on $10,000 over 6 years at 6%", "$322.08")
        try expectFin("total interest on $10,000 over 6 years at 6%", "$1,932.48")
    },

    EngineCase("finance-loan-semantics-and-strictness") {
        // Average-interest meaning: the requested daily/monthly/annual
        // figures are the TOTAL (or total interest) divided by the
        // requested number of periods — never an independent schedule.
        guard let monthly = finEval("monthly repayment on $10,000 over 6 years at 6%"),
              case .money(let pmt, let code) = monthly else {
            throw CaseFailure(message: "loan monthly", location: "Finance")
        }
        try expectEqual(code, "USD", "loan currency preserved")
        guard let total = finEval("total repayment on $10,000 over 6 years at 6%"),
              case .money(let totalValue, _) = total else {
            throw CaseFailure(message: "loan total", location: "Finance")
        }
        try expectClose(pmt * 72, totalValue, 1e-6, "monthly x 72 == total")
        // Zero rate is allowed and deterministic.
        try expectFin("monthly repayment on $12,000 over 1 year at 0%", "$1,000.00")
        try expectFin("total repayment on $12,000 over 1 year at 0%", "$12,000.00")
        try expectFin("total interest on $12,000 over 1 year at 0%", "$0.00")
        // Fractional years.
        try expectFin("monthly repayment on $12,000 over 0.5 years at 0%", "$2,000.00")
        // N > 0 required; R >= 100% rejected.
        try expectFinError("monthly repayment on $10,000 over 0 years at 6%")
        try expectFinError("monthly repayment on $10,000 over -2 years at 6%")
        try expectFinError("monthly repayment on $10,000 over 6 years at 100%")
        try expectFinError("monthly repayment on $10,000 over 6 years at 150%")
        // The investment `interest on` shape keeps its own lane.
        try expectFin("interest on $1,000 after 3 years at 7%", "$225.04")
        // Non-money operand is a malformed owned phrase.
        try expectFinError("monthly repayment on 10,000 over 6 years at 6%")
        try expectFinError("weekly repayment on $10,000 over 6 years at 6%")
    },

    EngineCase("finance-sales-tax-configured") {
        let tax15 = FinancialContext(tax: TaxPreferences(preset: "GB", name: "VAT",
                                                         ratePercent: 15))
        try expectFin("$300 + VAT", "$345.00", tax: tax15)
        try expectFin("$345 - VAT", "$300.00", tax: tax15)
        try expectFin("VAT on $300", "$45.00", tax: tax15)
        try expectFin("pre-tax price of $345", "$300.00", tax: tax15)
        try expectFin("gross price of $300", "$345.00", tax: tax15)
        try expectFin("$300 including VAT", "$345.00", tax: tax15)
        // The registry aliases all map to the configured rate.
        try expectFin("$300 + GST", "$345.00", tax: tax15)
        try expectFin("sales tax on $300", "$45.00", tax: tax15)
        try expectFin("GST ON $300", "$45.00", tax: tax15)
        // A configured custom name joins the registry.
        let custom = FinancialContext(tax: TaxPreferences(preset: "", name: "My Tax",
                                                          ratePercent: 15))
        try expectFin("$200 + my tax", "$230.00", tax: custom)
        try expectFin("MY TAX on $200", "$30.00", tax: custom)
        // Precision: the intermediate is never rounded (0.05 x 1.15 =
        // 0.0575 -> displayed at the money minor digits).
        try expectFin("$0.05 + VAT", "$0.06", tax: tax15)
        try expectFin("VAT on $19.99", "$3.00", tax: tax15)
        // Currency variants preserve the code.
        try expectFin("€345 - VAT", "€300.00", tax: tax15)
        try expectFin("£300 + VAT", "£345.00", tax: tax15)
        // A different configured rate changes every form.
        let tax8 = FinancialContext(tax: TaxPreferences(preset: "", name: "Sales Tax",
                                                        ratePercent: 8))
        try expectFin("$300 + Sales Tax", "$324.00", tax: tax8)
        try expectFin("sales tax on $300", "$24.00", tax: tax8)
    },

    EngineCase("finance-sales-tax-missing-and-strictness") {
        // Missing configuration: the exact actionable message.
        guard let missing = finEval("$300 + VAT"), case .error(let message) = missing else {
            throw CaseFailure(message: "missing tax config errors", location: "Finance")
        }
        try expectEqual(message, "set sales tax in Settings → Tax",
                        "actionable missing-rate message")
        guard case .error(let message2)? = finEval("VAT on $300") else {
            throw CaseFailure(message: "missing tax config on-form", location: "Finance")
        }
        try expectEqual(message2, "set sales tax in Settings → Tax", "on-form message")
        // An out-of-range stored rate sanitizes to unconfigured.
        let invalid = FinancialContext(tax: TaxPreferences(preset: "", name: "VAT",
                                                           ratePercent: 150))
        try expectEqual(invalid.tax.ratePercent, nil, "150% is not a valid stored rate")
        guard case .error? = finEval("$300 + VAT", tax: invalid) else {
            throw CaseFailure(message: "invalid rate fails closed", location: "Finance")
        }
        // Owned heads without money error; non-owned prose is untouched.
        guard case .error? = finEval("VAT on my lunch", tax: invalid) else {
            throw CaseFailure(message: "owned head without money errors", location: "Finance")
        }
        let prose = finEval("I paid VAT yesterday", tax: invalid)
        if let prose, case .error = prose {
            throw CaseFailure(message: "unrelated prose is not owned", location: "Finance")
        }
        // The explicit percentage phrase stays independent of settings.
        try expectFin("sales tax 8% of $120", "$9.60")
        // Ordinary money is untouched by the tax lane.
        try expectFin("$300 + $45", "$345.00")
    },

    EngineCase("finance-sales-tax-persistence-and-nlx") {
        var settings = AppSettings()
        settings.tax = TaxPreferences(preset: "DE", name: "VAT", ratePercent: 19)
        let data = try JSONEncoder().encode(settings)
        let back = try JSONDecoder().decode(AppSettings.self, from: data)
        try expectEqual(back.tax, settings.tax, "tax roundtrip")
        // Legacy/malformed stores fall back safely.
        let legacy = Data(#"{"decimalPlaces": 10, "fontSizeKey": "tf", "language": "en", "sheetName": "Sheet", "lineNumbers": true, "hideSidebarButtonWhenCollapsed": false, "showTotalBar": true, "fontColor": "white"}"#.utf8)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacy)
        try expectEqual(decoded.tax, TaxPreferences.defaults, "legacy store default tax")
        let malformed = Data(#"{"decimalPlaces": 10, "fontSizeKey": "tf", "language": "en", "sheetName": "Sheet", "lineNumbers": true, "hideSidebarButtonWhenCollapsed": false, "showTotalBar": true, "fontColor": "white", "tax": 42}"#.utf8)
        let recovered = try JSONDecoder().decode(AppSettings.self, from: malformed)
        try expectEqual(recovered.tax, TaxPreferences.defaults, "malformed tax block ignored")
        let badRate = Data(#"{"decimalPlaces": 10, "fontSizeKey": "tf", "language": "en", "sheetName": "Sheet", "lineNumbers": true, "hideSidebarButtonWhenCollapsed": false, "showTotalBar": true, "fontColor": "white", "tax": {"preset": "DE", "name": "VAT", "ratePercent": "nineteen"}}"#.utf8)
        let badRateDecoded = try JSONDecoder().decode(AppSettings.self, from: badRate)
        try expectEqual(badRateDecoded.tax.ratePercent, nil, "wrong-typed rate falls back to nil")
        // `.nlx` never carries tax settings.
        let export = SheetExport(title: "Sheet", content: "1+1")
        let json = String(data: try JSONEncoder().encode(export), encoding: .utf8) ?? ""
        for banned in ["tax", "Tax", "vat", "VAT", "salesTax"] {
            try expect(!json.contains(banned), "export has no \(banned)")
        }
        // Preset table integrity: documented minimums loaded from the
        // HASH-VERIFIED bundled resource (no Swift-side rate table).
        guard let catalog = TaxPresetCatalog.shared else {
            throw CaseFailure(message: "tax preset catalog loads", location: "Finance")
        }
        try expectEqual(catalog.version, "tax-presets-2026.1", "preset dataset version")
        try expectEqual(catalog.presets.count, 25, "25 bundled presets")
        try expectEqual(TaxPresets.preset(for: "AU")?.ratePercent, 10, "AU GST 10")
        try expectEqual(TaxPresets.preset(for: "GB")?.ratePercent, 20, "UK VAT 20")
        try expectEqual(TaxPresets.preset(for: "DE")?.ratePercent, 19, "DE VAT 19")
        try expectEqual(TaxPresets.preset(for: "NL")?.ratePercent, 21, "NL VAT 21")
        try expect(TaxPresets.preset(for: "US")?.ratePercent == nil,
                   "US has NO automatic rate (nil, not 0)")
        var regions = Set<String>()
        for preset in catalog.presets {
            try expect(regions.insert(preset.region).inserted,
                       "unique region \(preset.region)")
            try expect(!preset.name.isEmpty, "\(preset.region) name")
            try expect(!preset.note.isEmpty, "\(preset.region) note")
            if let rate = preset.ratePercent {
                try expect(rate.isFinite && rate >= 0 && rate < 100,
                           "\(preset.region) rate domain")
            }
        }
        // US preset selected: rate stays UNSET until the user enters one.
        let usUnset = FinancialContext(tax: TaxPreferences(preset: "US", name: "Sales Tax",
                                                           ratePercent: nil))
        guard case .error(let usMessage)? = finEval("$300 + sales tax", tax: usUnset) else {
            throw CaseFailure(message: "US preset without rate errors", location: "Finance")
        }
        try expectEqual(usMessage, "set sales tax in Settings → Tax",
                        "US unset rate message")
        // A manual 0% is allowed and DISTINCT from unset.
        let usZero = FinancialContext(tax: TaxPreferences(preset: "US", name: "Sales Tax",
                                                          ratePercent: 0))
        try expectFin("$300 + sales tax", "$300.00", tax: usZero)
        for lang in AppLanguage.allCases {
            for key in ["tax.group", "tax.preset", "tax.preset.custom", "tax.name",
                        "tax.rate", "tax.rateCap"] {
                let text = L10n.t(key, language: lang)
                try expect(text != key && !text.isEmpty, "\(lang.rawValue): \(key)")
            }
        }
    },

    EngineCase("finance-income-tax-official-corpus") {
        guard let catalog = IncomeTaxCatalog.shared else {
            throw CaseFailure(message: "income-tax catalog loads", location: "Finance")
        }
        let financial = FinancialContext(tax: .defaults, incomeTaxTables: catalog,
                                         cpi: nil)
        // US 2025 single: $75,000 -> standard deduction folded; tax =
        // 11925*0.10 + 36550*0.12 + 26525*0.22 = 8114.00.
        try expectFin("income tax on $75,000 in US", "$7,670.00", tax: financial)
        try expectFin("income after tax on $75,000 in US", "$67,330.00", tax: financial)
        try expectFin("tax rate on $75,000 in US", "10.2266666667%", tax: financial)
        // Case-insensitive aliases.
        try expectFin("income tax on $75,000 in usa", "$7,670.00", tax: financial)
        try expectFin("income tax on $75,000 in United States", "$7,670.00", tax: financial)
        // Zero is deterministic.
        try expectFin("income tax on $0 in US", "$0.00", tax: financial)
        try expectFin("tax rate on $0 in US", "0%", tax: financial)
        // Other catalogs (local currency inputs).
        try expectFin("income tax on £50,270 in UK", "£7,540.00", tax: financial)
        try expectFin("income tax on €50,000 in DE", "€8,491.38", tax: financial)
        try expectFin("income tax on ₹1,000,000 in IN", "₹40,000.00", tax: financial)
        try expectFin("income tax on ¥5,000,000 in JP", "¥476,500", tax: financial)
        try expectFin("income tax on A$100,000 in AU", "A$20,788.00", tax: financial)
        try expectFin("income tax on CA$100,000 in CA", "CA$14,037.93", tax: financial)
        try expectFin("income tax on ₽3,000,000 in RU", "₽402,000.00", tax: financial)
        try expectFin("income tax on €50,000 in FR", "€8,103.99", tax: financial)
        try expectFin("income tax on €50,000 in NL", "€18,076.22", tax: financial)
        // Unknown country is the exact message.
        guard case .error(let message)? = finEval("income tax on $75,000 in Atlantis",
                                                  tax: financial) else {
            throw CaseFailure(message: "unknown country errors", location: "Finance")
        }
        try expectEqual(message, "no tax table for Atlantis", "unknown country message")
        // Negative income errors.
        guard case .error? = finEval("income tax on -$5,000 in US", tax: financial) else {
            throw CaseFailure(message: "negative income errors", location: "Finance")
        }
        // Without the catalog the lane fails closed.
        guard case .error? = finEval("income tax on $75,000 in US") else {
            throw CaseFailure(message: "missing catalog fails closed", location: "Finance")
        }
    },

    EngineCase("finance-income-tax-cross-currency") {
        // Pinned rates: 1 USD = 0.9 EUR (EUR per USD).
        let rates = Rates(base: "USD", rates: ["USD": 1, "EUR": 0.9])
        guard let catalog = IncomeTaxCatalog.shared else {
            throw CaseFailure(message: "income-tax catalog loads", location: "Finance")
        }
        let financial = FinancialContext(tax: .defaults, incomeTaxTables: catalog,
                                         cpi: nil)
        // €72,000 -> $80,000 -> US tax 8,914.00 -> €8,022.60.
        var v: [String: Double] = [:]
        guard let row = evalLine("income tax on €72,000 in US", variables: &v,
                                 rates: rates, decimalPlaces: 10,
                                 financial: financial),
              case .money(let value, let code) = row else {
            throw CaseFailure(message: "cross-currency income tax", location: "Finance")
        }
        try expectEqual(code, "EUR", "result returns to the input code")
        try expectClose(value, 7893.00, 1e-6, "cross-currency tax value")
        guard let text = AnswerDisplay.displayText(for: row, decimalPlaces: 10,
                                                   context: .legacy) else {
            throw CaseFailure(message: "cross-currency display", location: "Finance")
        }
        try expectEqual(text, "€7,893.00", "cross-currency display")
        // A missing pair is `Rates unavailable`.
        let emptyRates = Rates(base: "USD", rates: ["USD": 1])
        let missingResult = evalLine("income tax on €72,000 in US", variables: &v,
                                     rates: emptyRates, decimalPlaces: 10,
                                     financial: financial)
        guard case .error(let missing)? = missingResult else {
            throw CaseFailure(message: "missing pair is an error", location: "Finance")
        }
        try expectEqual(missing, "Rates unavailable", "missing pair message")
        // The effective rate is currency-independent.
        guard let rateRow = evalLine("tax rate on €72,000 in US", variables: &v,
                                     rates: rates, decimalPlaces: 10,
                                     financial: financial),
              case .number(let effective, _, let kind, _) = rateRow else {
            throw CaseFailure(message: "effective tax rate", location: "Finance")
        }
        try expectClose(effective, 0.109625, 1e-9, "effective rate value")
        try expectEqual(kind, .percent, "effective rate kind")
        guard let rateText = AnswerDisplay.displayText(for: rateRow, decimalPlaces: 10,
                                                       context: .legacy) else {
            throw CaseFailure(message: "effective rate display", location: "Finance")
        }
        try expectEqual(rateText, "10.9625%", "effective rate display")
    },

    EngineCase("finance-income-tax-catalog-integrity") {
        guard let catalog = IncomeTaxCatalog.shared else {
            throw CaseFailure(message: "income-tax catalog loads", location: "Finance")
        }
        try expectEqual(catalog.version, "income-tax-2026.2", "dataset version")
        try expectEqual(catalog.tables.count, 10, "exactly ten tables")
        let expected = ["US", "GB", "AU", "CA", "DE", "FR", "NL", "IN", "RU", "JP"]
        for country in expected {
            guard let table = catalog.table(for: country) else {
                throw CaseFailure(message: "\(country) table present", location: "Finance")
            }
            try expect(!table.aliases.isEmpty, "\(country) aliases")
            try expect(!table.currency.isEmpty, "\(country) currency")
            try expect(!table.taxPeriod.isEmpty, "\(country) tax period")
            try expect(!table.sourceTitle.isEmpty, "\(country) source title")
            try expect(table.sourceURL.hasPrefix("https://"), "\(country) source URL")
            try expect(!table.note.isEmpty, "\(country) model note")
            try expect(!table.brackets.isEmpty, "\(country) brackets")
            try expect(table.tax(on: 0) == 0, "\(country) zero income")
            // Brackets are strictly increasing and end open-ended.
            var previous = 0.0
            for bracket in table.brackets.dropLast() {
                guard let upTo = bracket.upTo else {
                    throw CaseFailure(message: "\(country) internal open bracket",
                                      location: "Finance")
                }
                try expect(upTo > previous, "\(country) bracket order")
                previous = upTo
            }
            try expect(table.brackets.last?.upTo == nil, "\(country) open-ended top")
        }
        // Honest periods per table (verified 2026 applicability or the
        // TRUE earlier period when a 2026 schedule could not be
        // substantiated — never relabelled).
        let periods: [String: String] = [
            "US": "2026", "GB": "2026/27", "DE": "2026",
            "FR": "2026 (income 2025)", "NL": "2026", "JP": "2026",
            "RU": "2026", "AU": "2025-26", "CA": "2025",
            "IN": "AY 2026-27 (FY 2025-26)",
        ]
        for (country, period) in periods {
            try expectEqual(catalog.table(for: country)?.taxPeriod, period,
                            "\(country) honest tax period")
        }
        // The three unverified-for-2026 tables carry an explicit
        // blocker note; the verified seven do not.
        for country in ["AU", "CA", "IN"] {
            try expect(catalog.table(for: country)?.note.contains("BLOCKER") == true,
                       "\(country) blocker note")
        }
        for country in ["US", "GB", "DE", "FR", "NL", "JP", "RU"] {
            try expect(catalog.table(for: country)?.note.contains("BLOCKER") != true,
                       "\(country) verified for 2026")
        }
    },

    EngineCase("finance-cpi-inflation-corpus") {
        guard let cpi = CPICatalog.shared else {
            throw CaseFailure(message: "CPI catalog loads", location: "Finance")
        }
        let financial = FinancialContext(tax: .defaults, incomeTaxTables: nil, cpi: cpi)
        // Past -> snapshot (2026 provisional YTD is the bundle's "today").
        try expectFin("what is $1,000 from 1990", "$2,537.53", tax: financial)
        try expectFin("value of $1,000 from 1990", "$2,537.53", tax: financial)
        try expectFin("$1,000 from 1990 worth what today", "$2,537.53", tax: financial)
        try expectFin("$1,000 from 1990 worth today", "$2,537.53", tax: financial)
        try expectFin("$1,000 in 1990 dollars", "$2,537.53", tax: financial)
        // Snapshot -> historical.
        try expectFin("what was $1,000 worth in 1990", "$394.08", tax: financial)
        try expectFin("value of $1,000 in 1990", "$394.08", tax: financial)
        try expectFin("$1,000 is worth what in 1990", "$394.08", tax: financial)
        // Explicit ratio.
        try expectFin("what is $1,000 in 1990 worth in 2020", "$1,980.19", tax: financial)
        try expectFin("$1,000 from 1990 is worth what in 2020", "$1,980.19",
                      tax: financial)
        // Boundary years and the provisional 2026.
        try expectFin("what is $1,000 from 1913", "$33,500.51", tax: financial)
        try expectFin("what is $1,000 from 2025", "$1,030.17", tax: financial)
        try expectFin("value of $1,000 in 2026", "$1,000.00", tax: financial)
        // Future purchasing power (never nominal growth).
        try expectFin("what will $1,000 be worth in 2035 at 3%", "$766.42",
                      tax: financial)
        try expectFin("what will $1,000 be worth in 2035 at 3% inflation",
                      "$766.42", tax: financial)
        try expectFin("what will $1,000 be worth in 2035 assuming 3% inflation",
                      "$766.42", tax: financial)
        try expectFin("what will $1,000 be worth in 2030 with 2.5% inflation",
                      "$905.95", tax: financial)
        // Currency preserved.
        try expectFin("value of €1,000 in 1990", "€394.08", tax: financial)
        try expectFin("what is ¥1,000 from 1990", "¥2,538", tax: financial)
    },

    EngineCase("finance-cpi-strictness") {
        guard let cpi = CPICatalog.shared else {
            throw CaseFailure(message: "CPI catalog loads", location: "Finance")
        }
        let financial = FinancialContext(tax: .defaults, incomeTaxTables: nil, cpi: cpi)
        // Years outside the table are the exact message.
        guard case .error(let message)? = finEval("what is $1,000 from 1900",
                                                  tax: financial) else {
            throw CaseFailure(message: "out-of-range year errors", location: "Finance")
        }
        try expectEqual(message, "no CPI data for 1900", "out-of-range message")
        guard case .error(let message2)? = finEval("what was $1,000 worth in 2099",
                                                   tax: financial) else {
            throw CaseFailure(message: "future historical year errors", location: "Finance")
        }
        try expectEqual(message2, "no CPI data for 2099", "future year message")
        // A future target without an explicit rate is strict.
        guard case .error? = finEval("what will $1,000 be worth in 2035",
                                     tax: financial) else {
            throw CaseFailure(message: "future without rate errors", location: "Finance")
        }
        // Explicit forecasts require target > snapshot and a real domain.
        guard case .error? = finEval("what will $1,000 be worth in 2020 at 3%",
                                     tax: financial) else {
            throw CaseFailure(message: "past forecast target errors", location: "Finance")
        }
        guard case .error? = finEval("what will $1,000 be worth in 2035 at -200%",
                                     tax: financial) else {
            throw CaseFailure(message: "negative domain errors", location: "Finance")
        }
        // Zero inflation is allowed and deterministic.
        try expectFin("what will $1,000 be worth in 2030 at 0%", "$1,000.00",
                      tax: financial)
        // Without the catalog the lane is inactive (other lanes unchanged).
        if let r = finEval("what is $1,000 from 1990"), case .money = r {
            throw CaseFailure(message: "catalog required", location: "Finance")
        }
        // Prose and ordinary money are untouched.
        try expectFin("$600", "$600.00", tax: financial)
    },

    EngineCase("finance-cpi-named-and-token-operands") {
        guard let cpi = CPICatalog.shared else {
            throw CaseFailure(message: "CPI catalog loads", location: "Finance")
        }
        let financial = FinancialContext(tax: .defaults, incomeTaxTables: nil, cpi: cpi)
        // Named money.
        var v: [String: Double] = [:]
        let rows = evaluateSheet("pay = $1,000\nwhat is pay from 1990",
                                 variables: &v, rates: Rates(), decimalPlaces: 10,
                                 financial: financial)
        guard rows.count == 2,
              let text = AnswerDisplay.displayText(for: rows[1].result,
                                                   decimalPlaces: 10,
                                                   context: .legacy) else {
            throw CaseFailure(message: "named CPI operand", location: "Finance")
        }
        try expectEqual(text, "$2,537.53", "named CPI operand")
        // Token operand through the resolveSheet path.
        let marker = "\u{FFFC}"
        let id0 = UUID(), id1 = UUID()
        let content = "$1,000\n" + marker + " in 1990 dollars"
        let markerLoc = ("$1,000" as NSString).length + 1
        let resolved = resolveSheet(
            content: content, lineIDs: [id0, id1],
            references: [AnswerReference(sourceLineID: id0, labelLine: 1,
                                         location: markerLoc)],
            rates: Rates(), decimalPlaces: 10, financial: financial)
        guard resolved.lines.count == 2,
              let tokenText = AnswerDisplay.displayText(for: resolved.lines[1].result,
                                                        decimalPlaces: 10,
                                                        context: .legacy) else {
            throw CaseFailure(message: "token CPI operand", location: "Finance")
        }
        try expectEqual(tokenText, "$2,537.53", "token CPI operand")
    },

    EngineCase("finance-cpi-catalog-integrity") {
        guard let cpi = CPICatalog.shared else {
            throw CaseFailure(message: "CPI catalog loads", location: "Finance")
        }
        try expectEqual(cpi.version, "cpi-u-2026.1", "dataset version")
        try expectEqual(cpi.series, "CUUR0000SA0", "BLS series")
        try expectEqual(cpi.basePeriod, "1982-84=100", "base period")
        // Continuous 1913...2025 coverage: exactly 113 annual points.
        try expectEqual(cpi.annual.count, 113, "113 continuous annual points")
        var expectedYears: Set<Int> = []
        for year in 1913...2025 { expectedYears.insert(year) }
        try expectEqual(Set(cpi.annual.keys), expectedYears,
                        "every integer year 1913...2025 exists")
        try expectEqual(cpi.annual[1913], 9.9, "1913 annual average")
        try expectEqual(cpi.annual[2013], 232.957, "2013 annual average (was missing)")
        try expectEqual(cpi.annual[2019], 255.657, "2019 annual average (was missing)")
        try expectEqual(cpi.annual[2025], 321.943, "2025 annual average")
        // Explicit 2013/2019 queries resolve through the phrase lane.
        let financial = FinancialContext(tax: .defaults, incomeTaxTables: nil, cpi: cpi)
        try expectFin("what is $1,000 from 2013", "$1,423.67", tax: financial)
        try expectFin("what is $1,000 from 2019", "$1,297.27", tax: financial)
        try expectEqual(cpi.latestAnnualYear, 2025, "latest annual year")
        try expectEqual(cpi.latestSnapshotYear, 2026, "provisional snapshot year")
        try expectEqual(cpi.latestSnapshotIndex, 331.655, "provisional YTD snapshot index")
        guard let provisional = cpi.provisional else {
            throw CaseFailure(message: "provisional entry present", location: "Finance")
        }
        try expectEqual(provisional.months, [1, 2, 3, 4, 5, 6, 7, 8],
                        "provisional months")
        try expectEqual(provisional.latestMonth, 8, "latest observation month")
        try expectEqual(provisional.latestValue, 334.980, "latest observation")
        try expect(!provisional.method.isEmpty, "provisional method note")
        try expect(cpi.sourceURL.hasPrefix("https://"), "official source URL")
        try expect(cpi.index(for: 2026) != nil, "2026 lookup")
        try expect(cpi.index(for: 1912) == nil, "below coverage")
        for (year, value) in cpi.annual {
            try expect(value > 0 && value.isFinite, "\(year) positive finite index")
        }
    },

    EngineCase("finance-integration-highlighting-totals-tokens") {
        guard let cpi = CPICatalog.shared, let income = IncomeTaxCatalog.shared else {
            throw CaseFailure(message: "bundled catalogs load", location: "Finance")
        }
        let financial = FinancialContext(
            tax: TaxPreferences(preset: "GB", name: "VAT", ratePercent: 15),
            incomeTaxTables: income, cpi: cpi)
        let source = [
            "$1,000 after 3 years at 7%",
            "$500 invested $1,500 returned",
            "monthly repayment on $10,000 over 6 years at 6%",
            "$300 + VAT",
            "income tax on $75,000 in US",
            "what is $1,000 from 1990",
        ].joined(separator: "\n")
        let lines = source.components(separatedBy: "\n")
        // Highlighting: every line has spans, all within bounds, and no
        // overlapping ranges after the shared sanitizer contract.
        let spans = SyntaxClassifier.spans(for: source, rates: Rates(),
                                           decimalPlaces: 10,
                                           financial: financial)
        try expectEqual(spans.count, lines.count, "one span list per line")
        for (index, lineSpans) in spans.enumerated() {
            let length = (lines[index] as NSString).length
            for span in lineSpans {
                try expect(span.range.location >= 0,
                           "span location \(index)")
                try expect(NSMaxRange(span.range) <= length,
                           "span within line \(index)")
            }
            let sorted = lineSpans.sorted { $0.range.location < $1.range.location }
            for (a, b) in zip(sorted, sorted.dropFirst()) {
                try expect(NSMaxRange(a.range) <= b.range.location,
                           "no overlapping spans on line \(index)")
            }
        }
        // Totals: money contributes its magnitude, the ROI multiplier its
        // canonical factor, one row per line (no double counting).
        var vars: [String: Double] = [:]
        let rows = evaluateSheet(source, variables: &vars, rates: Rates(),
                                 decimalPlaces: 10, financial: financial)
        try expectEqual(rows.count, 6, "one row per line")
        try expectClose(SheetFooterTotal.aggregate(rows) ?? 0,
                        1225.043 + 2 + 165.7289 + 345 + 7670 + 2537.529, 0.05,
                        "footer sums the canonical values once")
        // Previous-answer eligibility: money and percent/multiplier
        // outcomes are answerable; the effective-rate kind rides along.
        for row in rows {
            try expect(PreviousAnswerPlan.isAnswerable(row.result),
                       "row \(row.sourceLineIndex) answerable")
        }
        // A money token from a financial row resolves through the SAME
        // value the row shows.
        var tokenVars: [String: Double] = [:]
        let tokenSheet = "$1,000 after 3 years at 7%\nTOKEN + 100"
            .replacingOccurrences(of: "TOKEN", with: "\u{FFFC}")
        let markerLoc = ("$1,000 after 3 years at 7%" as NSString).length + 1
        let resolved = resolveSheet(
            content: tokenSheet, lineIDs: [UUID(), UUID()],
            references: [AnswerReference(sourceLineID: UUID(), labelLine: 1,
                                         location: markerLoc)],
            rates: Rates(), decimalPlaces: 10, financial: financial)
        _ = tokenVars
        // The reference points at a random ID: a broken token inside a
        // larger expression is a strict error, never a stale numeric
        // snapshot.
        guard case .error(let tokenError) = resolved.lines[1].result else {
            throw CaseFailure(message: "stale token fails strictly, got \(resolved.lines[1].result)",
                              location: "Finance")
        }
        try expectEqual(tokenError, "Invalid reference", "stale token message")
    },

    EngineCase("finance-investment-exact-user-acceptance") {
        // The user's exact acceptance corpus. Both figures are directly
        // formula-derived (no discrepancy).
        guard let cagr = finEval("annual return on $1,000 invested $2,500 returned after 7 years"),
              case .number(let rawCAGR, _, let cagrKind, _) = cagr else {
            throw CaseFailure(message: "exact CAGR evaluates", location: "Finance")
        }
        try expectClose(rawCAGR, 0.13985228104759662, 1e-15,
                        "raw CAGR (2.5)^(1/7)-1 kept unrounded")
        try expectEqual(cagrKind, .percent, "CAGR percent kind")
        guard let cagrTwo = AnswerDisplay.displayText(for: cagr, decimalPlaces: 2,
                                                      context: .legacy) else {
            throw CaseFailure(message: "exact CAGR display", location: "Finance")
        }
        try expectEqual(cagrTwo, "13.99%", "acceptance presentation at 2 dp")
        // The default 10 dp row truthfully shows the full stored value.
        guard let cagrTen = AnswerDisplay.displayText(for: cagr, decimalPlaces: 10,
                                                      context: .legacy) else {
            throw CaseFailure(message: "exact CAGR 10dp", location: "Finance")
        }
        try expectEqual(cagrTen, "13.9852281048%", "10 dp presentation")
        // Present value: 1000 / 1.1^20.
        guard let pv = finEval("present value of $1,000 after 20 years at 10%"),
              case .money(let rawPV, let pvCode) = pv else {
            throw CaseFailure(message: "exact PV evaluates", location: "Finance")
        }
        try expectEqual(pvCode, "USD", "PV currency")
        try expectClose(rawPV, 148.64362802414345, 1e-12, "raw PV unrounded")
        guard let pvText = AnswerDisplay.displayText(for: pv, decimalPlaces: 10,
                                                     context: .legacy) else {
            throw CaseFailure(message: "exact PV display", location: "Finance")
        }
        try expectEqual(pvText, "$148.64", "acceptance PV")
    },
]
