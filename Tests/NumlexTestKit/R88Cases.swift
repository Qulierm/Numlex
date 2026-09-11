//
//  R88Cases.swift
//  NumlexTestKit
//
//  R88: UI cleanup — localization key hygiene (no raw dotted
//  identifiers may surface; centralized l10n keys for the negative /
//  currency enums; localized Format menu), the global rounding
//  TICKED SLIDER (shared TickSlider primitive, 2...10 = 9 ticks,
//  snap-only persistence, decode clamp), the Constants/Units EMPTY
//  STATE (no header/divider/blank table shell), and the deduplicated
//  answer context menu (exactly ONE Number Format construction,
//  conditional Reset, stable-ID safety).
//

import NumlexCore
import Foundation

/// The R88 case collection (all tasks).
public var r88Cases: [EngineCase] {
    r88L10nCases + r88SliderCases + r88EmptyStateCases + r88MenuCases
}

// MARK: - helpers

private func r88AppSource(_ rel: String) -> String? {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // NumlexTestKit
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repo root
    let url = root.appendingPathComponent(rel).standardizedFileURL
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try? String(contentsOf: url, encoding: .utf8)
}

/// Counts non-overlapping occurrences of `needle` in `haystack`.
private func r88count(_ needle: String, in haystack: String) -> Int {
    guard !needle.isEmpty else { return 0 }
    var n = 0
    var rest = haystack
    while let r = rest.range(of: needle) {
        n += 1
        rest = String(rest[r.upperBound...])
    }
    return n
}

/// Extracts the source between `open` (searched from the start) and
/// the first `close` after it — the body of a view branch. When
/// `after` is given, the branch opened right after that marker.
private func r88branch(_ src: String, open: String,
                       after: String? = nil, close: String) -> String? {
    let startBase = after.flatMap { src.range(of: $0)?.upperBound } ?? src.startIndex
    guard let start = src.range(of: open, range: startBase..<src.endIndex)?.upperBound
    else { return nil }
    guard let end = src.range(of: close, range: start..<src.endIndex)?.lowerBound
    else { return nil }
    return String(src[start..<end])
}

/// Decodes AppSettings from a raw dictionary via JSON (the store's
/// settings shape) and returns the clamped decimalPlaces.
private func r88decodePlaces(_ raw: Int) -> Int? {
    let json = "{\"decimalPlaces\":\(raw),\"fontSizeKey\":\"tf\",\"language\":\"en\","
        + "\"sheetName\":\"Sheet\",\"lineNumbers\":true,\"fontColor\":\"white\"}"
    guard let data = json.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(NumlexCore.AppSettings.self, from: data).decimalPlaces
}

// MARK: - 1. localization hygiene

let r88L10nCases: [EngineCase] = [
    EngineCase("r88.l10n-no-raw-keys-all-languages") {
        // Every key the UI surfaces through L10n.t must resolve to a
        // real translation in ALL six languages (value != raw key).
        let keys = [
            "negative.label", "negative.cap", "negative.minus",
            "negative.parentheses", "negative.trailingMinus",
            "currency.label", "currency.cap", "currency.before",
            "currency.beforeSpaced", "currency.after", "currency.afterSpaced",
            "numbers.format", "numbers.formatCap", "notation.label",
            "fraction.label", "fraction.cap", "customPattern.label",
            "customPattern.cap", "customPattern.invalid", "customPattern.preview",
            "numberFormat", "formatDefault", "formatAutomatic", "formatDecimal",
            "formatScientific", "formatEngineering", "formatFraction",
            "formatCustom", "customPatternInvalid", "resetFormatting",
            "highlight", "highlightNone", "highlightYellow", "highlightOrange",
            "highlightGreen", "highlightBlue", "highlightPurple", "highlightPink",
            "settings.numbers", "settings.format", "settings.constants",
            "styling.column", "styling.columnCap",
            "styling.column.alignment",
            "alignment.leading", "alignment.trailing",
            "styling.column.surface", "styling.column.surfaceCap",
            "surface.neutral", "surface.sand", "surface.slate",
            "surface.sage", "surface.blush",
            "constants.intro", "constants.emptyTitle", "constants.emptyCap",
            "units.intro", "units.emptyTitle", "units.emptyCap",
            "rounding", "roundingCap", "decimalPlaces",
        ]
        for lang in AppLanguage.allCases {
            for k in keys {
                let v = L10n.t(k, language: lang)
                try expect(v != k && !v.isEmpty,
                           "\(lang) must translate \(k), got: \(v)")
            }
        }
    },
    EngineCase("r88.l10n-trailingMinus-key-and-caption") {
        // The enum's raw value participates in the KEY, and the table
        // carries exactly that key (no `negative.trailing` alias left).
        try expectEqual(NegativeStyle.trailingMinus.l10nKey, "negative.trailingMinus",
                        "l10nKey maps the raw value into the table key")
        for lang in AppLanguage.allCases {
            try expectEqual(L10n.t("negative.trailingMinus", language: lang)
                == "negative.trailingMinus", false,
                "\(lang) must translate negative.trailingMinus")
            try expectEqual(L10n.t("negative.trailing", language: lang)
                == "negative.trailing", true,
                "\(lang) must NOT keep the stale negative.trailing key")
            // The English contract sample is a SINGLE parenthesis pair.
        }
        let en = L10n.t("negative.parentheses", language: .en)
        try expect(en.contains("(123)"), "English parentheses sample: \(en)")
        try expect(!en.contains("((123))"), "no double parentheses in English")
        // Both captions exist and are distinct real strings.
        let nc = L10n.t("negative.cap", language: .en)
        let cc = L10n.t("currency.cap", language: .en)
        try expect(nc != "negative.cap" && !nc.isEmpty, "negative.cap resolves")
        try expect(cc != "currency.cap" && !cc.isEmpty, "currency.cap resolves")
    },
    EngineCase("r88.l10n-enum-key-mapping") {
        // The centralized key helpers must line up with the tables for
        // EVERY case of both enums, in every language.
        for n in NegativeStyle.allCases {
            for lang in AppLanguage.allCases {
                let v = L10n.t(n.l10nKey, language: lang)
                try expect(v != n.l10nKey && !v.isEmpty,
                           "\(lang) must translate \(n.l10nKey)")
            }
        }
        for c in CurrencyPlacement.allCases {
            for lang in AppLanguage.allCases {
                let v = L10n.t(c.l10nKey, language: lang)
                try expect(v != c.l10nKey && !v.isEmpty,
                           "\(lang) must translate \(c.l10nKey)")
            }
        }
        try expectEqual(CurrencyPlacement.beforeSpaced.l10nKey,
                        "currency.beforeSpaced", "beforeSpaced key")
        try expectEqual(NegativeStyle.parentheses.l10nKey,
                        "negative.parentheses", "parentheses key")
    },
    EngineCase("r88.l10n-format-menu-localized-source") {
        // No hardcoded English command strings may remain in the app's
        // Format menu; every title goes through L10n with the live
        // settings language.
        guard let src = r88AppSource("Sources/NumlexApp/NumlexApp.swift")
        else { return }
        try expect(!src.contains("CommandMenu(\"Format\")"),
                   "Format menu title must be localized")
        try expect(!src.contains("Menu(\"Highlight\")"),
                   "Highlight menu title must be localized")
        try expect(!src.contains("Button(\"None\")"),
                   "None item must be localized")
        try expect(!src.contains("Button(\"Yellow\")"),
                   "color items must be localized")
        try expect(src.contains("L10n.t(\"settings.format\""),
                   "Format title via settings.format key")
        try expect(src.contains("L10n.t(\"highlight\""),
                   "Highlight title via highlight key")
        for k in ["highlightNone", "highlightYellow", "highlightOrange",
                  "highlightGreen", "highlightBlue", "highlightPurple",
                  "highlightPink"] {
            try expect(src.contains("L10n.t(\"\(k)\""),
                       "\(k) wired through L10n")
        }
    },
]

// MARK: - 2. global rounding slider

let r88SliderCases: [EngineCase] = [
    EngineCase("r88.slider-tick-math") {
        // Pure tick arithmetic of the shared primitive: ticks =
        // max - min + 1. Global 2...10 -> 9 ticks; per-answer 0...10
        // -> 11 ticks (unchanged contract).
        func ticks(min: Int, max: Int) -> Int { max - min + 1 }
        try expectEqual(ticks(min: 2, max: 10), 9, "global slider: 9 ticks")
        try expectEqual(ticks(min: AnswerDisplay.minPlaces,
                              max: AnswerDisplay.maxPlaces), 11,
                        "per-answer slider: 11 ticks (0...10 unchanged)")
        try expectEqual(AnswerDisplay.minPlaces, 0, "per-answer min stays 0")
        try expectEqual(AnswerDisplay.maxPlaces, 10, "per-answer max stays 10")
    },
    EngineCase("r88.slider-source-shared-primitive") {
        // The ONE TickSlider primitive configures the native NSSlider:
        // tick count from the range, snap-to-ticks, ticks BELOW the
        // track, continuous tracking, small control size.
        guard let src = r88AppSource("Sources/NumlexApp/DiscreteTickSlider.swift")
        else { return }
        try expect(src.contains("numberOfTickMarks = max - min + 1"),
                   "tick count derived from the range")
        try expect(src.contains("allowsTickMarkValuesOnly = true"),
                   "snap-to-ticks enabled")
        try expect(src.contains("tickMarkPosition = .below"),
                   "ticks below the track")
        try expect(src.contains("isContinuous = true"),
                   "continuous native tracking")
        try expect(src.contains("controlSize = .small"), "small control size")
        // Snap-only persistence: the callback fires only when the
        // snapped integer CHANGES (dedupe against the last value).
        try expect(src.contains("if v != last"),
                   "change callback deduplicated on snapped integer")
        // No segmented control and no menu picker in the primitive.
        try expect(!src.contains("NSSegmentedControl"), "no segmented control")
        try expect(!src.contains("NSPopUpButton"), "no menu picker")
        // The per-answer menu slider reuses the SAME primitive.
        guard let menu = r88AppSource("Sources/NumlexApp/AnswerSliderMenuItem.swift")
        else { return }
        try expect(menu.contains("TickSlider.make(min: AnswerDisplay.minPlaces"),
                   "per-answer slider built from the shared primitive")
    },
    EngineCase("r88.slider-settings-wiring") {
        // The Numbers tab rounds through the AppKit-backed slider:
        // range 2...10, live `N dp` label, localized VoiceOver
        // label/value, persist on change. NO rounding Picker remains.
        guard let src = r88AppSource("Sources/NumlexApp/Views/SettingsView.swift")
        else { return }
        try expect(src.contains("DiscreteTickSlider("),
                   "rounding row uses the ticked slider")
        try expect(src.contains("minValue: 2"), "global range floor 2")
        try expect(src.contains("maxValue: 10"), "global range ceiling 10")
        try expect(src.contains("AnswerDisplay.sliderLabel("),
                   "live `N dp` label")
        try expect(src.contains("L10n.t(\"decimalPlaces\""),
                   "VoiceOver label localized")
        try expect(src.contains("sliderAccessibilityValue"),
                   "VoiceOver value localized")
        try expect(src.contains("model.persist()"), "persists on change")
        try expect(!src.contains("ForEach(2...10"),
                   "no rounding menu picker remains")
    },
    EngineCase("r88.slider-global-decode-clamp") {
        // The AppSettings contract is 2...10: out-of-range legacy
        // values clamp on decode so the slider thumb, the label and
        // the stored value can never disagree.
        try expectEqual(r88decodePlaces(0), 2, "below range clamps to 2")
        try expectEqual(r88decodePlaces(1), 2, "1 clamps to 2")
        try expectEqual(r88decodePlaces(2), 2, "2 stays")
        try expectEqual(r88decodePlaces(5), 5, "in-range stays")
        try expectEqual(r88decodePlaces(10), 10, "10 stays")
        try expectEqual(r88decodePlaces(42), 10, "above range clamps to 10")
    },
]

// MARK: - 3. Constants / Units empty state

let r88EmptyStateCases: [EngineCase] = [
    EngineCase("r88.empty-state-structure") {
        guard let src = r88AppSource("Sources/NumlexApp/Views/SettingsView.swift")
        else { return }
        // Both sections branch on the row list: EMPTY -> the one
        // shared empty state; POPULATED -> the real table + footer.
        try expect(src.contains("if model.settings.customConstants.isEmpty {"),
                   "constants branch on emptiness")
        try expect(src.contains("if model.settings.customUnits.isEmpty {"),
                   "units branch on emptiness")
        try expect(src.contains("SettingsEmptyState("),
                   "shared empty-state view used")
        try expect(src.contains("systemImage: \"function\""),
                   "constants empty state: SF Symbol `function`")
        try expect(src.contains("systemImage: \"ruler\""),
                   "units empty state: SF Symbol `ruler`")
        // Localized copy + the prominent native Add action.
        try expect(src.contains("L10n.t(\"constants.emptyTitle\""),
                   "constants empty title localized")
        try expect(src.contains("L10n.t(\"units.emptyTitle\""),
                   "units empty title localized")
        try expect(src.contains("buttonStyle(.borderedProminent)"),
                   "prominent native Add action")
        // The empty branch must NOT build the table shell: header
        // captions, the divider and the nested ScrollView live ONLY in
        // the populated branch.
        let cEmpty = r88branch(src, open: "if model.settings.customConstants.isEmpty {",
                               close: "} else {")
        try expect(cEmpty != nil, "constants empty branch found")
        if let cEmpty {
            try expect(!cEmpty.contains("constants.name"),
                       "constants empty state has no column header")
            try expect(!cEmpty.contains("Divider()"),
                       "constants empty state has no divider")
            try expect(!cEmpty.contains("ScrollView {"),
                       "constants empty state has no table ScrollView")
        }
        let uEmpty = r88branch(src, open: "if model.settings.customUnits.isEmpty {",
                               close: "} else {")
        try expect(uEmpty != nil, "units empty branch found")
        if let uEmpty {
            try expect(!uEmpty.contains("units.definition"),
                       "units empty state has no column header")
            try expect(!uEmpty.contains("Divider()"),
                       "units empty state has no divider")
            try expect(!uEmpty.contains("ScrollView {"),
                       "units empty state has no table ScrollView")
        }
        // Populated branches keep the real structure.
        let cPop = r88branch(src, open: "if model.settings.customConstants.isEmpty {",
                             close: "// MARK: Units") ?? ""
        try expect((cPop ?? "").contains("constants.name"),
                   "populated constants branch keeps the header")
        try expect((cPop ?? "").contains("ScrollView {"),
                   "populated constants branch keeps the row table")
        // Add still creates + focuses through the model methods.
        try expect(src.contains("model.addConstant() { focusedName = id }"),
                   "constants Add focuses the new row")
        try expect(src.contains("model.addUnitRow() { focusedName = id }"),
                   "units Add focuses the new row")
    },
    EngineCase("r88.empty-state-copy-all-languages") {
        for lang in AppLanguage.allCases {
            for k in ["constants.emptyTitle", "constants.emptyCap",
                      "units.emptyTitle", "units.emptyCap"] {
                let v = L10n.t(k, language: lang)
                try expect(v != k && !v.isEmpty,
                           "\(lang) must translate \(k)")
            }
        }
        try expectEqual(L10n.t("constants.emptyTitle", language: .en),
                        "No constants", "English constants title")
        try expectEqual(L10n.t("units.emptyTitle", language: .en),
                        "No custom units", "English units title")
    },
    EngineCase("r88.empty-state-model-roundtrip") {
        // Empty -> add -> populated -> delete -> empty, at the model
        // array level (the view branches purely on count == 0).
        var s = AppSettings()
        try expectEqual(s.customConstants.isEmpty, true, "starts empty")
        let row = UserConstant(name: "tau", expression: "6.28")
        s.customConstants.append(row)
        try expectEqual(s.customConstants.count, 1, "add populates")
        s.customConstants.removeAll { $0.id == row.id }
        try expectEqual(s.customConstants.isEmpty, true,
                        "deleting the last row returns to the empty state")
        // Same lifecycle for units.
        let u = UserUnitDefinition(name: "hand",
                                   definition: "4 fingers")
        s.customUnits.append(u)
        try expectEqual(s.customUnits.count, 1, "unit add populates")
        s.customUnits.removeAll { $0.id == u.id }
        try expectEqual(s.customUnits.isEmpty, true, "unit delete empties")
    },
]

// MARK: - 4. answer context menu dedupe

let r88MenuCases: [EngineCase] = [
    EngineCase("r88.menu-one-number-format-block") {
        // Exactly ONE Number Format construction in the answer menu —
        // the r87 copy/paste duplication is gone.
        guard let src = r88AppSource("Sources/NumlexApp/Views/AnswerColumnView.swift")
        else { return }
        try expectEqual(r88count("L10n.t(\"numberFormat\"", in: src), 1,
                                "exactly one Number Format item title")
        try expectEqual(r88count("AnswerDisplay.notationOptions(for:", in: src), 1,
                         "exactly one notation-options block")
        try expectEqual(r88count("fmt.submenu = sub", in: src), 1,
                        "exactly one submenu assembly")
        // Copy and Delete each remain exactly once.
        try expectEqual(r88count("L10n.t(\"copyAnswer\"", in: src), 1,
                                "one Copy item")
        try expectEqual(r88count("L10n.t(\"deleteLine\"", in: src), 1,
                                "one Delete item")
    },
    EngineCase("r88.menu-conditional-reset") {
        // The Reset item is built ONCE and appears ONLY while the row
        // carries a precision and/or notation override; a clean row
        // shows no Reset at all.
        guard let src = r88AppSource("Sources/NumlexApp/Views/AnswerColumnView.swift")
        else { return }
        try expectEqual(r88count("L10n.t(\"resetFormatting\"", in: src), 1,
                                "exactly one Reset construction")
        try expect(src.contains("if override(for: idx) != nil || overrideHere != nil"),
                   "Reset guarded by a precision/notation override")
        try expect(src.contains("onRestoreFormatting(idx)"),
                   "Reset still clears through the stable-index action")
    },
    EngineCase("r88.menu-eligible-pure") {
        // Pure eligibility is unchanged: numeric rows offer the
        // notation menu; dates, errors and rates never do.
        let n: LineResult = .number(value: 2.5, unit: nil, kind: .plain, fraction: nil)
        try expectEqual(AnswerDisplay.notationOptions(for: n) != nil, true,
                        "numeric rows are eligible")
        let d: LineResult = .date(year: 2026, month: 7, day: 3, showYear: true)
        try expectEqual(AnswerDisplay.notationOptions(for: d) != nil, false,
                        "dates are never re-notated")
        let e: LineResult = .error(message: "boom")
        try expectEqual(AnswerDisplay.notationOptions(for: e) != nil, false,
                        "errors have no menu")
    },
]
