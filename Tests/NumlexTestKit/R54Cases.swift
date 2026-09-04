import Foundation
import NumlexCore

/// r54: the answer context menu's inline precision SLIDER.
///
/// The AppKit menu itself (NSSlider item, caption, NSMenu material) is
/// thin over the PURE NumlexCore presentation helpers, which is what
/// this suite pins:
/// 1. Slider initial value = effective per-answer precision
///    (override ?? global), clamped 0...10; every tick is an integer;
/// 2. The visible label is the compact `N dp` (never fractional); the
///    accessibility value says decimal places in the active language;
/// 3. nil override inherits the global precision until the slider is
///    first moved; a move writes an explicit per-line override (no
///    reset control exists to clear it);
/// 4. R51 menu eligibility is unchanged (slider only for numeric
///    scalar/variable rows; money/currency, date, broken token and
///    `Rates unavailable` stay slider-less);
/// 5. New localization keys exist in every table (Russian exact);
/// 6. Source regression: the old Rounding submenu is gone from the
///    menu builder and the explicitly omitted controls (Speak Answer,
///    comma/M/$ buttons, Reset) are absent from the answer-menu code.

private func r54AppSource(_ rel: String) -> String? {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // NumlexTestKit
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repo root
    let url = root.appendingPathComponent(rel).standardizedFileURL
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try? String(contentsOf: url, encoding: .utf8)
}

public let r54Cases: [EngineCase] = [
    // MARK: 1. Initial value

    EngineCase("r54-slider-initial-nil-inherits-global") {
        try expectEqual(AnswerDisplay.sliderValue(defaultPlaces: 5, override: nil), 5,
                        "untouched row inherits the global precision")
        try expectEqual(AnswerDisplay.sliderValue(defaultPlaces: 2, override: nil), 2,
                        "global two shows at two")
    },

    EngineCase("r54-slider-initial-override-wins") {
        try expectEqual(AnswerDisplay.sliderValue(defaultPlaces: 2, override: 7), 7,
                        "explicit override wins")
        try expectEqual(AnswerDisplay.sliderValue(defaultPlaces: 10, override: 0), 0,
                        "an explicit zero is not 'no override'")
    },

    EngineCase("r54-slider-clamps-to-range") {
        try expectEqual(AnswerDisplay.sliderValue(defaultPlaces: 2, override: -3), 0,
                        "below-range override clamps to 0")
        try expectEqual(AnswerDisplay.sliderValue(defaultPlaces: 2, override: 15), 10,
                        "above-range override clamps to 10")
        try expectEqual(AnswerDisplay.sliderValue(defaultPlaces: 12, override: nil), 10,
                        "a stale global above range clamps too")
    },

    // MARK: 2. Labels

    EngineCase("r54-slider-integer-labels") {
        for p in 0...10 {
            try expectEqual(AnswerDisplay.sliderLabel(p), "\(p) dp",
                            "tick \(p) labels compactly")
        }
        try expectEqual(AnswerDisplay.sliderLabel(0), "0 dp", "first tick")
        try expectEqual(AnswerDisplay.sliderLabel(10), "10 dp", "last tick")
    },

    EngineCase("r54-slider-label-clamps") {
        try expectEqual(AnswerDisplay.sliderLabel(-2), "0 dp", "never below 0")
        try expectEqual(AnswerDisplay.sliderLabel(42), "10 dp", "never above 10")
    },

    // MARK: 3. Override semantics (no reset)

    EngineCase("r54-slider-override-after-movement") {
        // Before any touch: the row shows the global precision.
        try expectEqual(AnswerDisplay.effective(defaultPlaces: 4, override: nil), 4,
                        "nil override inherits")
        // The slider's onChange writes the snapped integer.
        let moved: Int? = 6
        try expectEqual(AnswerDisplay.effective(defaultPlaces: 4, override: moved), 6,
                        "movement pins an explicit override")
        try expectEqual(AnswerDisplay.sliderValue(defaultPlaces: 4, override: moved), 6,
                        "reopening the menu starts at the pinned value")
        // No reset control exists to clear it: the override stays.
        let stored = [AnswerDisplayPreference(lineID: UUID(), decimalPlaces: moved!)]
        let sanitized = AnswerDisplay.sanitize(stored, lineIDs: [stored[0].lineID])
        try expectEqual(sanitized.map(\.decimalPlaces), [6],
                        "the override persists (nothing clears it)")
    },

    // MARK: 4. Eligibility unchanged (R51)

    EngineCase("r54-slider-eligibility-unchanged") {
        try expectEqual(AnswerDisplay.menu(for: .number(value: 1, unit: nil)),
                        AnswerDisplay.Menu(showsActions: true, showsRounding: true),
                        "plain scalar gets the slider")
        try expectEqual(AnswerDisplay.menu(for: .number(value: 1, unit: "km")),
                        AnswerDisplay.Menu(showsActions: true, showsRounding: true),
                        "unit quantity gets the slider")
        try expectEqual(AnswerDisplay.menu(for: .variable(name: "x", value: 1)),
                        AnswerDisplay.Menu(showsActions: true, showsRounding: true),
                        "variable gets the slider")
        try expectEqual(AnswerDisplay.menu(for: .money(value: 1, code: "USD")),
                        AnswerDisplay.Menu(showsActions: true, showsRounding: false),
                        "natural money: no slider")
        try expectEqual(AnswerDisplay.menu(for: .number(value: 1, unit: "USD")),
                        AnswerDisplay.Menu(showsActions: true, showsRounding: false),
                        "currency quantity: no slider")
        try expectEqual(AnswerDisplay.menu(
            for: .date(year: 2026, month: 6, day: 17, showYear: false)),
            AnswerDisplay.Menu(showsActions: true, showsRounding: false),
            "date: no slider")
        try expectEqual(AnswerDisplay.menu(for: .brokenToken(line: 4)),
                        AnswerDisplay.Menu(showsActions: true, showsRounding: false),
                        "broken token: no slider")
        try expectEqual(AnswerDisplay.menu(for: .error(message: "Rates unavailable")),
                        AnswerDisplay.Menu(showsActions: true, showsRounding: false),
                        "rates state: no slider")
        try expectEqual(AnswerDisplay.menu(for: .error(message: "division by zero")),
                        nil, "generic error: no menu at all")
    },

    // MARK: 5. Accessibility + localization

    EngineCase("r54-slider-accessibility-value-localized") {
        for lang in AppLanguage.allCases {
            let v = AnswerDisplay.sliderAccessibilityValue(5, language: lang)
            let dp = L10n.t("decimalPlaces", language: lang)
            try expectEqual(v, "5 \(dp)", "spoken value in \(lang)")
        }
        try expectEqual(AnswerDisplay.sliderAccessibilityValue(5, language: .ru),
                        "5 знаков после запятой", "RU exact")
        try expectEqual(AnswerDisplay.sliderAccessibilityValue(10, language: .en),
                        "10 decimal places", "EN exact")
    },

    EngineCase("r54-l10n-new-keys-all-languages") {
        for lang in AppLanguage.allCases {
            for key in ["editAnswerFormatting", "decimalPlaces"] {
                let v = L10n.t(key, language: lang)
                try expect(!v.isEmpty && v != key,
                           "key \(key) translated", "\(lang)")
            }
        }
        try expectEqual(L10n.t("editAnswerFormatting", language: .ru),
                        "Изменение формата ответа", "RU caption exact")
        try expectEqual(L10n.t("decimalPlaces", language: .ru),
                        "знаков после запятой", "RU dp exact")
        try expectEqual(L10n.t("editAnswerFormatting", language: .en),
                        "Edit answer formatting", "EN caption")
    },

    // MARK: 6. Source regression: structure + omissions

    EngineCase("r54-source-no-old-submenu-no-forbidden-ui") {
        guard let view = r54AppSource("Sources/NumlexApp/Views/AnswerColumnView.swift")
        else { throw CaseFailure(message: "AnswerColumnView.swift not found") }
        guard let slider = r54AppSource("Sources/NumlexApp/AnswerSliderMenuItem.swift")
        else { throw CaseFailure(message: "AnswerSliderMenuItem.swift not found") }
        for (name, src) in [("AnswerColumnView", view), ("AnswerSliderMenuItem", slider)] {
            try expect(!src.contains("Speak Answer"), "Speak Answer absent from \(name)")
            try expect(!src.contains("Reset"), "Reset control absent from \(name)")
        }
        try expect(!slider.contains("NSButton"),
                   "no format buttons (, / M / $) in the slider item")
        // The old Rounding submenu is no longer built anywhere in the
        // menu (the L10n keys stay for backward compatibility, but the
        // submenu emission is gone).
        try expect(!view.contains("L10n.t(\"roundingDefault\""),
                   "old Default item no longer emitted")
        try expect(!view.contains("L10n.t(\"rounding\""),
                   "old Rounding submenu title no longer emitted")
        try expect(!view.contains(".submenu"),
                   "no submenu construction in the answer menu")
        // The new structure IS wired: slider item + centered caption +
        // the pure helpers drive both.
        try expect(view.contains("AnswerSliderMenuItem.menuItem"),
                   "slider item integrated")
        try expect(view.contains("AnswerSliderMenuItem.caption"),
                   "caption integrated")
        try expect(view.contains("AnswerDisplay.sliderValue"),
                   "initial value comes from the pure helper")
        try expect(slider.contains("numberOfTickMarks"),
                   "native discrete slider with tick marks")
        try expect(slider.contains("allowsTickMarkValuesOnly"),
                   "integer stepping only")
    },
]
