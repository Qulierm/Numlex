//
//  R87Cases.swift
//  NumlexTestKit
//
//  R87: flexible answer formatting (global notations, custom number
//  patterns, negative styles, currency placement, fractions), the
//  display-vs-copy pipeline (compact display, full-precision copy),
//  per-line notation overrides, and persistent line highlights.
//  Every default reproduces the pre-r87 shapes byte-for-byte.
//

import NumlexCore
import Foundation

/// The R87 case collection (all tasks).
public var r87Cases: [EngineCase] {
    r87ModelCases + r87PatternCases + r87NotationCases
    + r87MoneyCases + r87PipelineCases + r87MenuCases
}

// MARK: - helpers

func r87Prefs(_ mutate: (inout NumberPresentationPreferences) -> Void = { _ in })
    -> NumberPresentationPreferences {
    var p = NumberPresentationPreferences.defaults
    mutate(&p)
    return p
}

/// The validated pattern (a test precondition — failure is a bug).
func r87Pattern(_ raw: String) -> NumberPattern {
    switch NumberPattern.validate(raw) {
    case .success(let p): return p
    case .failure(let e):
        fatalError("r87: pattern \(raw) failed validation: \(e)")
    }
}

/// The compact-capable display context (R73 contract: 100000 → 100k).
func r87CompactContext() -> NumberFormatContext {
    NumberFormatContext.resolve(
        RegionalNumberPreferences(
            region: .northAmerica,
            convertForeignOnPaste: false,
            showThousandsSeparator: true,
            useCompactNotation: true))
}

// MARK: - 1. models & persistence

let r87ModelCases: [EngineCase] = [
    EngineCase("r87.pres-defaults") {
        // The defaults reproduce the pre-r87 presentation exactly.
        let d = NumberPresentationPreferences.defaults
        try expectEqual(d.notation, NumberNotation.automatic, "default notation")
        try expectEqual(d.customPattern, "", "default pattern")
        try expectEqual(d.fractionPreset, FractionPreset.e16, "default fraction preset")
        try expectEqual(d.negativeStyle, NegativeStyle.minus, "default negative style")
        try expectEqual(d.currencyPlacement, CurrencyPlacement.before, "default currency placement")
        // A store with NO presentation key decodes to the defaults.
        let s = try JSONDecoder().decode(AppSettings.self,
            from: Data(#"{"decimalPlaces":10,"fontSizeKey":"tf","language":"en","sheetName":"Sheet","lineNumbers":true,"fontColor":"white"}"#.utf8))
        try expectEqual(s.presentation, .defaults, "missing presentation block")
        // A malformed presentation block falls back per key.
        let s2 = try JSONDecoder().decode(AppSettings.self,
            from: Data(#"{"decimalPlaces":10,"fontSizeKey":"tf","language":"en","sheetName":"Sheet","lineNumbers":true,"fontColor":"white","presentation":{"notation":"bogus","fractionPreset":7}}"#.utf8))
        try expectEqual(s2.presentation.notation, NumberNotation.automatic, "malformed notation falls back")
        try expectEqual(s2.presentation.fractionPreset, FractionPreset.e16, "out-of-set preset falls back")
        try expectEqual(s2.presentation.negativeStyle, NegativeStyle.minus, "absent style defaults")
    },
    EngineCase("r87.pres-tolerant-decode") {
        // Key-by-key tolerance: unknown/malformed keys fall back per key.
        let d = try JSONDecoder().decode(
            NumberPresentationPreferences.self,
            from: Data(#"{"notation":"bogus","fractionPreset":7,"negativeStyle":42,"currencyPlacement":"nope"}"#.utf8))
        try expectEqual(d.notation, NumberNotation.automatic, "unknown notation")
        try expectEqual(d.fractionPreset, FractionPreset.e16, "out-of-set fraction preset")
        try expectEqual(d.negativeStyle, NegativeStyle.minus, "malformed negative style")
        try expectEqual(d.currencyPlacement, CurrencyPlacement.before, "unknown currency placement")
        // A valid mix keeps the valid keys.
        let d2 = try JSONDecoder().decode(
            NumberPresentationPreferences.self,
            from: Data(#"{"notation":"engineering","fractionPreset":64}"#.utf8))
        try expectEqual(d2.notation, NumberNotation.engineering, "valid notation kept")
        try expectEqual(d2.fractionPreset, FractionPreset.e64, "valid preset kept")
        try expectEqual(d2.negativeStyle, NegativeStyle.minus, "other keys still default")
    },
    EngineCase("r87.pref-notation-override") {
        // Per-line notation: absent = Default (follow the global).
        let p = try JSONDecoder().decode(
            AnswerDisplayPreference.self,
            from: Data(#"{"lineID":"\#(UUID())","decimalPlaces":3}"#.utf8))
        try expectEqual(p.notation, nil, "absent notation key")
        let p2 = try JSONDecoder().decode(
            AnswerDisplayPreference.self,
            from: Data(#"{"lineID":"\#(UUID())","decimalPlaces":3,"notation":"fraction"}"#.utf8))
        try expectEqual(p2.notation, AnswerNotationOverride.fraction, "notation round-trip")
        // A raw string that is not a known override decodes as
        // nil (tolerant: the override simply falls back to Default).
        let bogus = try JSONDecoder().decode(AnswerDisplayPreference.self,
            from: Data(#"{"lineID":"\#(UUID())","decimalPlaces":3,"notation":"nope"}"#.utf8))
        try expectEqual(bogus.notation, nil, "unknown override falls back to Default")
        // Round-trip of a stored override.
        let back = try JSONDecoder().decode(
            AnswerDisplayPreference.self,
            from: try JSONEncoder().encode(p2))
        try expectEqual(back, p2, "override round-trip")
    },
    EngineCase("r87.styling-column") {
        let d = try JSONDecoder().decode(
            StylingPreferences.self, from: Data("{}".utf8))
        try expectEqual(d.answerColumnAlignment, AnswerColumnAlignment.leading, "default alignment")
        try expectEqual(d.answerColumnSurface, AnswerColumnSurface.neutral, "default surface")
        let s = try JSONDecoder().decode(
            StylingPreferences.self,
            from: Data(#"{"answerColumnAlignment":"trailing","answerColumnSurface":"bogus"}"#.utf8))
        try expectEqual(s.answerColumnAlignment, AnswerColumnAlignment.trailing, "valid alignment kept")
        try expectEqual(s.answerColumnSurface, AnswerColumnSurface.neutral, "unknown surface falls back")
    },
    EngineCase("r87.highlight-sanitize") {
        let a = UUID(), b = UUID(), stale = UUID()
        let lineIDs = [b, a, UUID()]  // b first, a second
        let prefs = [
            LineHighlightPreference(lineID: stale, color: .yellow),  // stale → dropped
            LineHighlightPreference(lineID: a, color: .blue),
            LineHighlightPreference(lineID: b, color: .green),
            LineHighlightPreference(lineID: a, color: .pink),        // duplicate → first wins
        ]
        let kept = LineHighlightPreference.sanitize(prefs, lineIDs: lineIDs)
        try expectEqual(kept.map { $0.lineID }, [b, a], "current line order")
        try expectEqual(kept[0].color, HighlightColor.green, "b keeps first color")
        try expectEqual(kept[1].color, HighlightColor.blue, "a keeps first color (not pink)")
        try expectEqual(
            kept.contains { $0.lineID == stale }, false, "stale ID dropped")
    },
    EngineCase("r87.highlight-sheet-decode") {
        // A sheet with highlights: stale IDs sanitized, malformed
        // entries dropped, the sheet still decodes.
        let a = UUID(), stale = UUID()
        let json = #"{"id":"\#(a)","name":"T","title":"T","lineIDs":["\#(a)"],"content":"7 + 1","createdAt":0,"modifiedAt":0,"highlights":[{"lineID":"\#(a)","color":"pink"},{"lineID":"\#(stale)","color":"blue"},{"lineID":"\#(a)","color":"yellow"},{"lineID":"\#(a)","color":"nope"}]}"#
        let sheet = try JSONDecoder().decode(Sheet.self, from: Data(json.utf8))
        try expectEqual(sheet.highlights.count, 1, "one survivor")
        try expectEqual(sheet.highlights[0].lineID, a, "survivor is the live line")
        try expectEqual(sheet.highlights[0].color, HighlightColor.pink, "first valid wins")
        // A sheet WITHOUT the key decodes empty (legacy files).
        let legacy = try JSONDecoder().decode(
            Sheet.self, from: Data(#"{"id":"\#(a)","name":"L","title":"L","lineIDs":["\#(a)"],"content":"1","createdAt":0,"modifiedAt":0}"#.utf8))
        try expectEqual(legacy.highlights.count, 0, "legacy sheet decodes")
    },
]

// MARK: - 2. the custom number pattern engine

let r87PatternCases: [EngineCase] = [
    EngineCase("r87.pattern-valid") {
        let p = r87Pattern("#,##0.00").positive.primaryGrouping
        try expectEqual(p, 3, "grouping of #,##0.00")
        let percent = r87Pattern("0%")
        try expectEqual(percent.positive.percent, true, "percent section")
        try expectEqual(percent.positive.fracRequired, 0, "percent has no decimals")
        let cur = r87Pattern("\u{00A4}#,##0.00")
        try expectEqual(cur.positive.hasCurrency, true, "currency prefix section")
        try expectEqual(cur.positive.currencyPrefix, true, "currency is prefixed")
        let literal = r87Pattern("'$'#,##0.00")
        try expectEqual(literal.positive.literalPrefix, "$", "quoted literal prefix")
        let zero = try! r87Pattern("#,##0.00;;0")
        try expectEqual(zero.zero == nil, false, "explicit zero section present")
        try expectEqual(zero.zero!.intRequired, 1, "zero section digit count")
    },
    EngineCase("r87.pattern-invalid") {
        try expectEqual(NumberPattern.validate(""),
                    Result.failure(NumberPatternError.noSkeleton), "empty pattern")
        try expectEqual(NumberPattern.validate(String(repeating: "0", count: 97)),
                    Result.failure(NumberPatternError.tooLong), "overlong pattern")
        try expectEqual(NumberPattern.validate("0;0;0;0"),
                    Result.failure(NumberPatternError.tooManySections), "four sections")
        try expectEqual(NumberPattern.validate("'abc"),
                    Result.failure(NumberPatternError.unterminatedQuote), "unterminated quote")
        try expectEqual(NumberPattern.validate("zzz"),
                    Result.failure(NumberPatternError.badDigitOrder), "unknown skeleton char")
        try expectEqual(NumberPattern.validate("%"),
                    Result.failure(NumberPatternError.noSkeleton), "scaler alone has no skeleton")
        try expectEqual(NumberPattern.validate("0¤¤"),
                    Result.failure(NumberPatternError.multipleCurrencies), "two currency marks")
    },
    EngineCase("r87.pattern-render") {
        let ctx = NumberFormatContext.legacy
        let p = r87Pattern("#,##0.00")
        try expectEqual(NumberPresentation.renderPattern(p, value: 1234.567,
                                                     negativeStyle: .minus, context: ctx),
                    "1,234.57", "grouped two-decimal render")
        try expectEqual(NumberPresentation.renderPattern(p, value: -1234.567,
                                                     negativeStyle: .minus, context: ctx),
                    "-1,234.57", "negative magnitude via global style")
        let int = r87Pattern("#,##0")
        try expectEqual(NumberPresentation.renderPattern(int, value: 1234567,
                                                     negativeStyle: .minus, context: ctx),
                    "1,234,567", "integer grouping")
        let indian = r87Pattern("#,##,##0")
        try expectEqual(NumberPresentation.renderPattern(indian, value: 1234567,
                                                         negativeStyle: .minus, context: ctx),
                        "12,34,567", "secondary (Indian-style) grouping")
        let opt = r87Pattern("#,##0.##")
        try expectEqual(NumberPresentation.renderPattern(opt, value: 1234.5,
                                                     negativeStyle: .minus, context: ctx),
                    "1,234.5", "optional decimal trimmed")
        try expectEqual(NumberPresentation.renderPattern(opt, value: 1234,
                                                     negativeStyle: .minus, context: ctx),
                    "1,234.", "declared decimal keeps the point when empty")
        let pct = r87Pattern("0%")
        try expectEqual(NumberPresentation.renderPattern(pct, value: 0.25,
                                                     negativeStyle: .minus, context: ctx),
                    "25%", "percent shift (symbol re-attached)")
        let zero = try! r87Pattern("#,##0.00;;0")
        try expectEqual(NumberPresentation.renderPattern(zero, value: 0,
                                                     negativeStyle: .minus, context: ctx),
                    "0", "explicit zero section")
    },
    EngineCase("r87.pattern-int64") {
        // The exact Int64 path renders the full digit string (never a
        // Double): 10^15 + 1 has no Double representation.
        let v = Int64(1_000_000_000_000_000) + 1
        let ctx = NumberFormatContext.legacy
        try expectEqual(NumberPresentation.formatInt64(v, notation: .automatic,
                                                   precision: 6, prefs: .defaults, context: ctx),
                    "1,000,000,000,000,001", "automatic exact integer")
        try expectEqual(NumberPresentation.formatInt64(v, notation: .decimal,
                                                   precision: 6, prefs: .defaults, context: ctx),
                    "1,000,000,000,000,001", "decimal exact integer")
        try expectEqual(NumberPresentation.formatInt64(v, notation: .fraction,
                                                   precision: 6, prefs: .defaults, context: ctx),
                    "1000000000000001", "fraction of an integer is itself")
    },
]

// MARK: - 3. notations (scientific / engineering / fraction / negatives)

let r87NotationCases: [EngineCase] = [
    EngineCase("r87.notation-scientific") {
        let ctx = NumberFormatContext.legacy
        let f: (Double, Int) -> String = { v, p in
            NumberPresentation.format(v, category: .plain, notation: .scientific,
                                      precision: p, prefs: .defaults, context: ctx)
        }
        try expectEqual(f(1234.567, 2), "1.23e+3", "normalized mantissa, signed exponent")
        try expectEqual(f(0.00123, 2), "1.23e-3", "negative exponent")
        try expectEqual(f(0, 2), "0", "zero is plain")
        try expectEqual(f(-1234.567, 2), "-1.23e+3", "negative mantissa")
    },
    EngineCase("r87.notation-engineering") {
        let ctx = NumberFormatContext.legacy
        let f: (Double, Int) -> String = { v, p in
            NumberPresentation.format(v, category: .plain, notation: .engineering,
                                      precision: p, prefs: .defaults, context: ctx)
        }
        try expectEqual(f(12345.6, 2), "12.35e+3", "exponent a multiple of three")
        try expectEqual(f(0.000123, 2), "123e-6", "mantissa under a thousand")
        try expectEqual(f(1234.567, 2), "1.23e+3", "already aligned exponent")
    },
    EngineCase("r87.notation-decimal") {
        let ctx = NumberFormatContext.legacy
        let f: (Double, Int) -> String = { v, p in
            NumberPresentation.format(v, category: .plain, notation: .decimal,
                                      precision: p, prefs: .defaults, context: ctx)
        }
        try expectEqual(f(1234.567, 2), "1234.57", "fixed precision, trimmed")
        try expectEqual(f(1000, 0), "1,000", "whole values keep grouping")
        try expectEqual(f(-1000, 0), "-1,000", "grouped negative")
    },
    EngineCase("r87.notation-fraction") {
        let ctx = NumberFormatContext.legacy
        let prefs = r87Prefs { $0.fractionPreset = .e16 }
        let f: (Double) -> String = { v in
            NumberPresentation.format(v, category: .plain, notation: .fraction,
                                      precision: 6, prefs: prefs, context: ctx)
        }
        try expectEqual(f(0.75), "3/4", "proper fraction")
        try expectEqual(f(1.75), "1 3/4", "mixed fraction")
        try expectEqual(f(2.0), "2", "whole fraction is the integer")
        try expectEqual(f(0.3333333), "1/3", "bounded convergent within tolerance")
        // An irrational-ish value beyond the denominator bound falls
        // back to the decimal shape (never blank, never a crash).
        try expectEqual(f(0.123456789).count > 0, true, "fallback still renders")
    },
    EngineCase("r87.notation-negatives") {
        let ctx = NumberFormatContext.legacy
        let styles: [(NegativeStyle, String)] = [
            (.minus, "-123.4"),
            (.parentheses, "(123.4)"),
            (.trailingMinus, "123.4-"),
        ]
        for (style, expected) in styles {
            let prefs = r87Prefs { $0.negativeStyle = style }
            try expectEqual(
                NumberPresentation.format(-123.4, category: .plain,
                                          notation: .decimal, precision: 1,
                                          prefs: prefs, context: ctx),
                expected, "negative style \(style)")
        }
        // Zero never picks up a negative shape.
        let parens = r87Prefs { $0.negativeStyle = .parentheses }
        try expectEqual(NumberPresentation.format(0, category: .plain, notation: .decimal,
                                              precision: 1, prefs: parens, context: ctx),
                    "0", "zero is shape-free")
    },
]

// MARK: - 4. money (placement + fallback)

let r87MoneyCases: [EngineCase] = [
    EngineCase("r87.money-placement") {
        let ctx = NumberFormatContext.legacy
        let placements: [(CurrencyPlacement, String)] = [
            (.before, "$1,234.56"),
            (.beforeSpaced, "$ 1,234.56"),
            (.after, "1,234.56$"),
            (.afterSpaced, "1,234.56 $"),
        ]
        for (placement, expected) in placements {
            let prefs = r87Prefs { $0.currencyPlacement = placement }
            try expectEqual(NumberPresentation.formatMoney(1234.56, code: "USD",
                                                       notation: .automatic,
                                                       prefs: prefs, context: ctx),
                        expected, "placement \(placement)")
        }
        // Unknown codes keep the documented value + space + CODE once.
        try expectEqual(NumberPresentation.formatMoney(1234.56, code: "XYZ",
                                                   notation: .automatic,
                                                   prefs: .defaults, context: ctx),
                    "1,234.56 XYZ", "unknown code fallback")
        // Zero-decimal currencies have no minor digits.
        try expectEqual(NumberPresentation.formatMoney(1234, code: "JPY",
                                                   notation: .automatic,
                                                   prefs: .defaults, context: ctx),
                    "\u{00A5}1,234", "zero-decimal currency")
        // Money never fractionizes: the decimal shape stands in.
        let fracPrefs = r87Prefs { $0.notation = .fraction }
        try expectEqual(NumberPresentation.formatMoney(1234.56, code: "USD",
                                                   notation: .fraction,
                                                   prefs: fracPrefs, context: ctx),
                    "$1,234.56", "money ignores fraction notation")
    },
]

// MARK: - 5. the display-vs-copy pipeline

let r87PipelineCases: [EngineCase] = [
    EngineCase("r87.pipeline-compact-vs-copy") {
        // R73 exception preserved on the automatic default: the DISPLAY
        // row may compact while the COPY keeps full precision.
        let compact = r87CompactContext()
        let result: LineResult = .number(value: 100000, unit: nil, kind: .plain, fraction: nil)
        try expectEqual(
            AnswerDisplay.displayText(for: result, decimalPlaces: 6, context: compact),
            "100k", "display compacts on automatic")
        try expectEqual(
            AnswerDisplay.text(for: result, decimalPlaces: 6, context: compact),
            "100,000", "copy keeps full precision")
        // Non-automatic notations share ONE string for display and copy.
        let sci = AnswerDisplay.displayText(for: result, decimalPlaces: 6,
                                            context: compact, notation: .scientific)
        let sciCopy = AnswerDisplay.text(for: result, decimalPlaces: 6,
                                         context: compact, notation: .scientific)
        try expectEqual(sci, sciCopy, "scientific display == copy")
        try expectEqual(sci, "1e+5", "100000 scientific")
    },
    EngineCase("r87.pipeline-money-rows") {
        let ctx = NumberFormatContext.legacy
        let money: LineResult = .money(value: 1234.56, code: "USD")
        try expectEqual(AnswerDisplay.displayText(for: money, decimalPlaces: 6, context: ctx),
                    "$1,234.56", "money display")
        try expectEqual(AnswerDisplay.text(for: money, decimalPlaces: 6, context: ctx),
                    "$1,234.56", "money copy identical")
        // Integer lane takes the row notation; radix rows stay canonical.
        let hex: LineResult = .integer(value: 256, radix: 16)
        try expectEqual(AnswerDisplay.text(for: hex, decimalPlaces: 6, context: ctx),
                    "0x100", "radix text canonical")
        try expectEqual(
            AnswerDisplay.text(for: .integer(value: 1234567, radix: 10),
                               decimalPlaces: 6, context: ctx, notation: .engineering),
            "1.234567e+6", "decimal integer takes the row notation")
    },
]

// MARK: - 6. Number Format menu descriptors (pure)

let r87MenuCases: [EngineCase] = [
    EngineCase("r87.menu-eligibility") {
        let plain: LineResult = .number(value: 1.5, unit: nil, kind: .plain, fraction: nil)
        try expectEqual(AnswerDisplay.notationOptions(for: plain)?.allowsFraction,
                    true, "plain values may fraction")
        let percent: LineResult = .number(value: 0.25, unit: nil, kind: .percent, fraction: nil)
        try expectEqual(AnswerDisplay.notationOptions(for: percent)?.allowsFraction,
                    false, "percent never fractions")
        let money: LineResult = .number(value: 9.99, unit: "USD", kind: .plain, fraction: nil)
        try expectEqual(AnswerDisplay.notationOptions(for: money)?.allowsFraction,
                    false, "money never fractions")
        let fraction: LineResult = .number(value: 0.5, unit: nil, kind: .fraction,
                                           fraction: Rational(numerator: 1, denominator: 2))
        try expectEqual(AnswerDisplay.notationOptions(for: fraction) != nil,
                    false, "semantic fractions stay verbatim")
        let boolean: LineResult = .boolean(value: true)
        try expectEqual(AnswerDisplay.notationOptions(for: boolean) != nil,
                    false, "booleans have nothing to re-notation")
        let date: LineResult = .date(year: 2026, month: 7, day: 3, showYear: true)
        try expectEqual(AnswerDisplay.notationOptions(for: date) != nil,
                    false, "dates never re-notation")
        let error: LineResult = .error(message: "boom")
        try expectEqual(AnswerDisplay.notationOptions(for: error) != nil,
                    false, "errors have no menu")
    },
    EngineCase("r87.menu-shapes") {
        let plain: LineResult = .number(value: 1.5, unit: nil, kind: .plain, fraction: nil)
        let m = AnswerDisplay.menu(for: plain)
        try expectEqual(m?.showsActions, true, "plain rows offer actions")
        try expectEqual(m?.showsRounding, true, "plain rows offer rounding")
        let money: LineResult = .money(value: 9.99, code: "USD")
        let mm = AnswerDisplay.menu(for: money)
        try expectEqual(mm?.showsRounding, false, "money rows never round")
        try expectEqual(mm?.showsActions, true, "money rows offer actions")
        try expectEqual(AnswerDisplay.menu(for: .boolean(value: true)) != nil,
                    true, "boolean rows keep Copy")
    },
]
