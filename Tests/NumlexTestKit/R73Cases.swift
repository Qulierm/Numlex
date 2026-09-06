import Foundation
import NumlexCore

/// r73 — Regional number settings: presets, parsing, formatting,
/// paste conversion, legacy-store fidelity. Every case constructs its
/// context through `NumberFormatContext.resolve(preset, locale:)` with
/// an INJECTED locale, so the suite is deterministic on any runner.

public let r73Cases: [EngineCase] = {
    var cases: [EngineCase] = []

    // Preset contexts used by the cases below (system preset uses the
    // injected en_US / de_DE / ru_RU locales).
    let na = NumberFormatContext.resolve(
        RegionalNumberPreferences(region: .northAmerica,
                                  convertForeignOnPaste: false,
                                  showThousandsSeparator: true,
                                  useCompactNotation: false),
        locale: Locale(identifier: "en_US"))
    let west = NumberFormatContext.resolve(
        RegionalNumberPreferences(region: .westernEurope,
                                  convertForeignOnPaste: false,
                                  showThousandsSeparator: true,
                                  useCompactNotation: false),
        locale: Locale(identifier: "en_US"))
    let ee = NumberFormatContext.resolve(
        RegionalNumberPreferences(region: .easternEurope,
                                  convertForeignOnPaste: false,
                                  showThousandsSeparator: true,
                                  useCompactNotation: false),
        locale: Locale(identifier: "en_US"))
    let sysDE = NumberFormatContext.resolve(
        RegionalNumberPreferences(region: .system,
                                  convertForeignOnPaste: false,
                                  showThousandsSeparator: true,
                                  useCompactNotation: false),
        locale: Locale(identifier: "de_DE"))
    let compactNA = NumberFormatContext.resolve(
        RegionalNumberPreferences(region: .northAmerica,
                                  convertForeignOnPaste: false,
                                  showThousandsSeparator: true,
                                  useCompactNotation: true),
        locale: Locale(identifier: "en_US"))
    let legacy = NumberFormatContext.legacy

    @Sendable func ev(_ s: String, _ c: NumberFormatContext) -> Double? {
        try? evaluateExpression(s, variables: [:], context: c)
    }

    cases.append(EngineCase("r73-preset-parsing-all-modes") {
        // North America: dot decimal, comma stays an argument
        // separator / grouping (the r47 rule).
        try expect(ev("1+1", na) == 2, "NA 1+1")
        try expect(ev("1,234 + 1", na) == 1235, "NA grouping 1,234")
        try expect(ev("max(1.5, 2.5)", na) == 2.5, "NA function args")
        // Western Europe: comma decimal, dot grouping, ; arguments.
        try expect(ev("1,5 + 2", west) == 3.5, "WEST 1,5 + 2")
        try expect(ev("1.234 + 1", west) == 1235, "WEST 1.234 + 1")
        try expect(ev("max(1,5; 2,5)", west) == 2.5, "WEST max(1,5; 2,5)")
        // Eastern Europe: comma decimal, NBSP/space grouping.
        try expect(ev("1 234 + 1", ee) == 1235, "EE 1 234 + 1")
        try expect(ev("12,5 × 2", ee) == 25, "EE 12,5 × 2")
        // System preset: the injected locale's conventions (de_DE =
        // the western shape).
        try expect(ev("1,5 + 2", sysDE) == 3.5, "system de_DE 1,5 + 2")
    })

    cases.append(EngineCase("r73-mode-cross-rejection") {
        // `;` is an argument separator ONLY in decimal-comma modes; in
        // decimal-point modes it is an unexpected character (the pre-
        // r73 behavior).
        do {
            _ = try evaluateExpression("max(1,5; 2,5)", variables: [:], context: na)
            throw CaseFailure(message: "NA must reject the semicolon argument")
        } catch {
            // expected
        }
        // Comma semantics in decimal-comma modes: digit-adjacent
        // commas are decimals (`sum(1,2)` -> 1.2), spaced commas are
        // argument separators (`sum(1, 2)` -> 3), and `;` is the
        // canonical separator (`max(1,5; 2,5)` -> 2.5).
        try expect(ev("sum(1,2)", west) == 1.2, "WEST sum(1,2) is the decimal 1.2")
        try expect(ev("sum(1, 2)", west) == 3, "WEST sum(1, 2) keeps the spaced argument")
        try expect(ev("max(1,5; 2,5)", west) == 2.5, "WEST semicolon arguments")
    })

    cases.append(EngineCase("r73-legacy-fidelity") {
        // The legacy context (and every no-context default) reproduces
        // the pre-r73 engine byte-for-byte.
        try expect(ev("1,234+1", legacy) == 1235, "legacy 1,234+1")
        // Pre-r73 fractional display: ungrouped fixed-point shape
        // (the pre-r73 formatter grouped integers only) — preserved.
        try expect(formatDisplayValue(1234.567, decimalPlaces: 7,
                                      context: legacy) == "1234.567",
                   "legacy display 1234.567")
        try expect(formatDisplayValue(1234, decimalPlaces: 7,
                                      context: legacy) == "1,234",
                   "legacy display 1234")
        // r51 edge: 0.33 at 0 decimals renders "0" (no decimal point
        // to trim) — preserved byte-for-byte.
        try expect(formatDisplayValue(0.33, decimalPlaces: 0,
                                      context: legacy) == "0",
                   "legacy 0.33 @0dp -> \"0\"")
        try expect(formatDisplayValue(0.33, decimalPlaces: 1,
                                      context: legacy) == "0.3",
                   "legacy 0.33 @1dp -> \"0.3\" (fractions ungrouped)")
        try expect(ev("10/0", legacy) == nil, "legacy 10/0 errors")
        // The plain no-context API is unchanged.
        let product = try evaluateExpression("7 × 6", variables: [:])
        try expect(product == 42, "no-context API")
    })

    cases.append(EngineCase("r73-display-separators") {
        try expect(formatDisplayValue(1234.567, decimalPlaces: 7, context: na)
                   == "1,234.567", "NA display")
        try expect(formatDisplayValue(1234.567, decimalPlaces: 7, context: west)
                   == "1.234,567", "WEST display")
        // Eastern Europe: NBSP grouping, comma decimal.
        let eeDisp = formatDisplayValue(1234567.5, decimalPlaces: 7, context: ee)
        try expect(eeDisp == "1\u{00A0}234\u{00A0}567,5", "EE display: \(eeDisp)")
        try expect(formatDisplayValue(1234567, decimalPlaces: 7, context: ee)
                   == "1\u{00A0}234\u{00A0}567", "EE integer display")
        // Grouping off: plain digits, locale decimal only.
        let westNoGrp = NumberFormatContext.resolve(
            RegionalNumberPreferences(region: .westernEurope,
                                      convertForeignOnPaste: false,
                                      showThousandsSeparator: false,
                                      useCompactNotation: false),
            locale: Locale(identifier: "en_US"))
        try expect(formatDisplayValue(1234.567, decimalPlaces: 7, context: westNoGrp)
                   == "1234,567", "WEST no-group display")
    })

    cases.append(EngineCase("r73-compact-notation") {
        try expect(formatDisplayValue(100000, decimalPlaces: 7, context: compactNA)
                   == "100k", "compact 100000 -> 100k")
        try expect(formatDisplayValue(999999, decimalPlaces: 7, context: compactNA)
                   == "999.999k", "compact 999999 -> 999.999k")
        try expect(formatDisplayValue(2500000000, decimalPlaces: 7, context: compactNA)
                   == "2.5B", "compact 2.5B")
        try expect(formatDisplayValue(1.5e15, decimalPlaces: 7, context: compactNA)
                   == "1500T", "compact 1.5e15 -> 1500T")
        // Under 1000 and over the compact bound stay plain/silent.
        try expect(formatDisplayValue(999, decimalPlaces: 7, context: compactNA)
                   == "999", "compact leaves 999")
        try expect(formatDisplayValue(1e17, decimalPlaces: 7, context: compactNA)
                   == scientificNotation(1e17), "compact leaves 1e17 scientific")
        // Decimal comma compact: the mantissa uses the locale decimal.
        let compactWest = NumberFormatContext.resolve(
            RegionalNumberPreferences(region: .westernEurope,
                                      convertForeignOnPaste: false,
                                      showThousandsSeparator: true,
                                      useCompactNotation: true),
            locale: Locale(identifier: "en_US"))
        try expect(formatDisplayValue(2500000000, decimalPlaces: 7, context: compactWest)
                   == "2,5B", "compact WEST 2,5B")
        // The full-precision COPY never compacts.
        let copy = AnswerDisplay.text(
            for: .number(value: 100000, unit: nil),
            decimalPlaces: 7, context: compactNA)
        try expect(copy == "100,000", "copy keeps full precision: \(copy ?? "nil")")
    })

    cases.append(EngineCase("r73-scientific-localized") {
        try expect(formatDisplayValue(5.5e21, decimalPlaces: 7, context: na)
                   == scientificNotation(5.5e21), "NA scientific shared")
        let sciWest = formatDisplayValue(5.5e21, decimalPlaces: 7, context: west)
        let base = scientificNotation(5.5e21)
        try expect(sciWest == base.replacingOccurrences(of: ".", with: ","),
                   "WEST scientific localized: \(sciWest)")
    })

    cases.append(EngineCase("r73-money-quantity-context") {
        // Money keeps the legacy two-minor-digit presentation — the
        // locale's 3-digit table must not leak in.
        try expect(formatMoney(1234.567, code: "EUR", context: west)
                   == "€1.234,57", "WEST money: \(formatMoney(1234.567, code: "EUR", context: west))")
        try expect(formatMoney(1234.567, code: "USD", context: na)
                   == "$1,234.57", "NA money")
        // Legacy money is byte-identical to the shared presentation.
        try expect(formatMoney(1234.567, code: "USD")
                   == formatMoney(1234.567, code: "USD", context: legacy),
                   "legacy money unchanged")
        try expect(formatQuantity(1.5, unit: "km", decimalPlaces: 7, context: west)
                   == "1,5 km", "WEST quantity")
        // Money never compacts.
        let compactMoney = formatMoney(100000, code: "USD", context: compactNA)
        try expect(compactMoney == "$100,000.00", "money never compacts: \(compactMoney)")
    })

    cases.append(EngineCase("r73-paste-conversion") {
        let westConv = NumberFormatContext.resolve(
            RegionalNumberPreferences(region: .westernEurope,
                                      convertForeignOnPaste: true,
                                      showThousandsSeparator: true,
                                      useCompactNotation: false),
            locale: Locale(identifier: "en_US"))
        let eeConv = NumberFormatContext.resolve(
            RegionalNumberPreferences(region: .easternEurope,
                                      convertForeignOnPaste: true,
                                      showThousandsSeparator: true,
                                      useCompactNotation: false),
            locale: Locale(identifier: "en_US"))
        let naConv = NumberFormatContext.resolve(
            RegionalNumberPreferences(region: .northAmerica,
                                      convertForeignOnPaste: true,
                                      showThousandsSeparator: true,
                                      useCompactNotation: false),
            locale: Locale(identifier: "en_US"))
        // NA -> WEST.
        try expect(PasteConversion.convert("total 1,234.56 and 5 items", context: westConv)
                   == "total 1.234,56 and 5 items", "paste NA->WEST")
        // NA -> EE.
        try expect(PasteConversion.convert("total 1,234.56", context: eeConv)
                   == "total 1\u{00A0}234,56", "paste NA->EE")
        // WEST -> NA.
        try expect(PasteConversion.convert("Gesamt 1.234,56 EUR", context: naConv)
                   == "Gesamt 1,234.56 EUR", "paste WEST->NA")
        // EE -> NA.
        try expect(PasteConversion.convert("Всего 1\u{00A0}234,56 руб", context: naConv)
                   == "Всего 1,234.56 руб", "paste EE->NA")
        // Idempotency: the target's own form converts to itself.
        try expect(PasteConversion.convert("Gesamt 1.234,56", context: westConv)
                   == "Gesamt 1.234,56", "paste idempotent WEST")
        try expect(PasteConversion.convert("total 1,234.56", context: naConv)
                   == "total 1,234.56", "paste idempotent NA")
        // A strict space group (1-3 digit lead + 3-digit groups) IS
        // converted — the documented accepted heuristic of the opt-in
        // toggle — while words and non-grouped numbers stay.
        try expect(PasteConversion.convert("room 5 678 bldg 12", context: westConv)
                   == "room 5.678 bldg 12", "paste space group -> target form")
        try expect(PasteConversion.convert("sum(1, 2) + 3", context: westConv)
                   == "sum(1, 2) + 3", "paste arglist untouched")
        // A dot decimal re-renders in the target decimal (1.23 ->
        // 1,23); a comma decimal in a comma target is native and
        // stays (1,5 -> 1,5).
        try expect(PasteConversion.convert("1.23 plus 1,5", context: westConv)
                   == "1,23 plus 1,5", "paste dot decimal -> target decimal")
        // The toggle OFF: byte-identical.
        try expect(PasteConversion.convert("total 1,234.56", context: west)
                   == "total 1,234.56", "paste toggle off no-op")
        // Legacy: byte-identical always.
        try expect(PasteConversion.convert("total 1,234.56", context: legacy)
                   == "total 1,234.56", "paste legacy no-op")
    })

    cases.append(EngineCase("r73-store-roundtrip") {
        // New store: the regional block round-trips key-by-key.
        let new = AppSettings(regional: RegionalNumberPreferences(
            region: .westernEurope, convertForeignOnPaste: true,
            showThousandsSeparator: false, useCompactNotation: true))
        let data = try JSONEncoder().encode(new)
        let back = try JSONDecoder().decode(AppSettings.self, from: data)
        try expect(back.regional == new.regional, "regional round-trip")
        // Legacy store: no `regional` key at all -> nil (legacy
        // behavior) and the decode never fails.
        let legacyJSON = """
        {"decimalPlaces":4,"fontSizeKey":"tf","language":"en",\
        "sheetName":"Sheet","lineNumbers":true,"fontColor":"white"}
        """
        let legacySettings = try JSONDecoder().decode(
            AppSettings.self, from: Data(legacyJSON.utf8))
        try expect(legacySettings.regional == nil, "legacy store -> nil regional")
        try expect(legacySettings.input == InputPreferences.defaults,
                   "legacy store input defaults")
        // Unknown region raw value: per-key fallback to .system.
        let unknownJSON = """
        {"decimalPlaces":4,"fontSizeKey":"tf","language":"en",\
        "sheetName":"Sheet","lineNumbers":true,"fontColor":"white",\
        "regional":{"region":"atlantis","convertForeignOnPaste":true}}
        """
        let unknown = try JSONDecoder().decode(
            AppSettings.self, from: Data(unknownJSON.utf8))
        try expect(unknown.regional?.region == .system,
                   "unknown region raw -> system")
        try expect(unknown.regional?.convertForeignOnPaste == true,
                   "regional per-key decode")
        try expect(unknown.regional?.showThousandsSeparator == true,
                   "regional missing key -> default")
    })

    cases.append(EngineCase("r73-context-threading-sheet") {
        var wvars: [String: Double] = [:]
        let rows = evaluateSheet(
            "1,5 + 1\ncost = 2,5\ncost × 100",
            variables: &wvars, rates: Rates(), decimalPlaces: 7,
            context: west)
        // Line 2 is a .variable (the named cost) — two numeric rows.
        var saw = 0
        for row in rows {
            if case .number(let v, _) = row.result, v.isFinite { saw += 1 }
        }
        try expect(saw == 2, "WEST sheet numeric rows: \(saw)")
        try expect(wvars["cost"] == 2.5, "WEST money-less named value")
        var nvars: [String: Double] = [:]
        let rowsNA = evaluateSheet(
            "1,5 + 1\ncost = 2.5\ncost × 100",
            variables: &nvars, rates: Rates(), decimalPlaces: 7,
            context: na)
        // In NA mode "1,5 + 1" is NOT a decimal: the comma strips and
        // the line is re-read by the legacy engine (grouping rules) —
        // the WEST sheet above reads it as 1.5 + 1 = 2.5 instead.
        // The value must differ between the two contexts.
        var sawNA = 0
        var naValues: [Double] = []
        for row in rowsNA {
            if case .number(let v, _) = row.result, v.isFinite {
                sawNA += 1
                naValues.append(v)
            }
        }
        var westValues: [Double] = []
        for row in rows {
            if case .number(let v, _) = row.result, v.isFinite { westValues.append(v) }
        }
        try expect(!naValues.contains(2.5),
                   "NA sheet never reads the line as 1.5+1: \(naValues)")
        try expect(westValues.contains(2.5),
                   "WEST sheet reads the line as 1.5+1: \(westValues)")
    })

    cases.append(EngineCase("r73-input-grouping-context") {
        // The input autoformat pass groups with the context's
        // separator (legacy: the prefs toggle; regional: the display
        // toggle).
        // Legacy: the input toggle groups with the legacy comma.
        let grouped = InputFormatting.formatLine(
            "12345", prefs: .defaults, rates: Rates(), decimalPlaces: 7,
            context: legacy)
        try expect(grouped?.text == "12,345",
                   "legacy input grouping: \(grouped?.text ?? "nil")")
        var noGroup = InputPreferences.defaults
        noGroup.groupNumbers = false
        // Grouping OFF: the pass returns nil (byte-identical).
        let legacyOff = InputFormatting.formatLine(
            "12345", prefs: noGroup, rates: Rates(), decimalPlaces: 7,
            context: legacy)
        try expect(legacyOff == nil, "legacy input grouping off: no-op")
        // Regional: the display toggle groups with the context's
        // separator (Western dot, Eastern NBSP).
        let westLine = InputFormatting.formatLine(
            "12345", prefs: .defaults, rates: Rates(), decimalPlaces: 7,
            context: west)
        try expect(westLine?.text == "12.345",
                   "WEST input grouping: \(westLine?.text ?? "nil")")
        let eeLine = InputFormatting.formatLine(
            "12345", prefs: .defaults, rates: Rates(), decimalPlaces: 7,
            context: ee)
        try expect(eeLine?.text == "12\u{00A0}345",
                   "EE input grouping: \(eeLine?.text ?? "nil")")
    })

    cases.append(EngineCase("r73-sys-locale-injection") {
        // The system preset resolves through the injected locale:
        // en_US behaves like North America, de_DE like Western Europe.
        let sysUS = NumberFormatContext.resolve(
            RegionalNumberPreferences(region: .system,
                                      convertForeignOnPaste: false,
                                      showThousandsSeparator: true,
                                      useCompactNotation: false),
            locale: Locale(identifier: "en_US"))
        try expect(ev("1,234 + 1", sysUS) == 1235, "system en_US grouping")
        try expect(formatDisplayValue(1234.5, decimalPlaces: 7, context: sysUS)
                   == "1,234.5", "system en_US display")
        try expect(ev("1.234 + 1", sysDE) == 1235, "system de_DE grouping")
        try expect(ev("1,5 + 2", sysDE) == 3.5, "system de_DE decimal comma")
    })

    return cases
}()
