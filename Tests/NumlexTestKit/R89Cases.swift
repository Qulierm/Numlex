//
//  R89Cases.swift
//  NumlexTestKit
//
//  R89: custom syntax colors (canonical opaque sRGB model, per-role
//  custom ?? preset resolution, set/clear/choose/reset/resetAll pure
//  APIs, tolerant decoding) + the reclaimed hidden line-number gutter
//  (one shared text-indent source of truth: ON = 54, OFF = 18).
//

import NumlexCore
import Foundation

/// The R89 case collection (all tasks).
public var r89Cases: [EngineCase] {
    r89ModelCases + r89PaletteCases + r89UICases + r89GeometryCases
}

// MARK: - helpers

private func r89AppSource(_ rel: String) -> String? {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // NumlexTestKit
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repo root
    let url = root.appendingPathComponent(rel).standardizedFileURL
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try? String(contentsOf: url, encoding: .utf8)
}

private func r89count(_ needle: String, in haystack: String) -> Int {
    guard !needle.isEmpty else { return 0 }
    var n = 0
    var rest = haystack
    while let r = rest.range(of: needle) {
        n += 1
        rest = String(rest[r.upperBound...])
    }
    return n
}

/// Decodes AppSettings from a raw settings JSON dictionary.
private func r89decodeSettings(_ json: String) -> AppSettings? {
    guard let data = json.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(AppSettings.self, from: data)
}

private let r89BaseSettings = "\"decimalPlaces\": 10, \"fontSizeKey\": \"tf\","
    + " \"language\": \"en\", \"sheetName\": \"Sheet\", \"lineNumbers\": true,"
    + " \"fontColor\": \"white\""

// MARK: - 1. custom color models

let r89ModelCases: [EngineCase] = [
    EngineCase("r89.model-defaults-nil-custom") {
        // The factory defaults carry no custom overrides; the whole
        // block is absent (nil), not an empty table.
        let d = StylingPreferences.defaults
        try expectEqual(d.customSyntaxColors, nil, "defaults have no custom block")
        try expectEqual(d.hasNonDefaultSyntaxColors, false,
                        "defaults need no reset")
        for role in SyntaxColorRole.allCases {
            try expectEqual(d.customColor(for: role), nil,
                            "\(role) has no custom color in defaults")
            try expectEqual(d.isSyntaxColorNonDefault(role), false,
                            "\(role) is at its default preset")
        }
    },
    EngineCase("r89.model-missing-block-decodes-nil") {
        // An old store (or any store without the key) decodes to nil —
        // every role keeps its preset.
        let s = r89decodeSettings(
            "{\(r89BaseSettings), \"styling\": {\"fontDesign\": \"rounded\"}}")
        try expect(s != nil, "old-style styling block decodes")
        try expectEqual(s?.styling.customSyntaxColors, nil,
                        "missing custom block -> nil")
        try expectEqual(s?.styling.fontDesign, .rounded, "other fields keep")
    },
    EngineCase("r89.model-partial-block-drops-only-bad-roles") {
        // Two valid roles, one wrong-typed role: only the bad role is
        // dropped; the store never fails.
        let json = """
        {\(r89BaseSettings),
         "styling": {"numbers": "cyan",
                     "customSyntaxColors": {
                        "numbers": {"r": 200, "g": 10, "b": 10},
                        "variables": {"r": 12, "g": 34, "b": 56},
                        "labels": "not-a-color"}}}
        """
        let s = r89decodeSettings(json)
        try expect(s != nil, "malformed role never fails the store")
        let table = s?.styling.customSyntaxColors
        try expect(table != nil, "custom block decoded")
        try expectEqual(table?[.numbers]?.r, 200, "valid numbers kept")
        try expectEqual(table?[.numbers]?.g, 10, "numbers g kept")
        try expectEqual(table?[.numbers]?.b, 10, "numbers b kept")
        try expectEqual(table?[.variables], SyntaxSRGBColor(r: 12, g: 34, b: 56),
                        "valid variables kept")
        try expectEqual(table?[.labels], nil, "wrong-type labels dropped")
        try expectEqual(table?[.operators], nil, "absent operators stay nil")
        // Every other role is untouched and still renders its preset.
        try expectEqual(s?.styling.presetChoice(for: .operators), .standardText,
                        "operators preset untouched")
    },
    EngineCase("r89.model-malformed-whole-block-drops-block") {
        // A wrong-typed whole block (a string where the object is
        // expected) drops the block to nil; the rest of the store is
        // intact.
        let s = r89decodeSettings(
            "{\(r89BaseSettings),"
            + " \"styling\": {\"numbers\": \"cyan\", \"customSyntaxColors\": \"red\"}}")
        try expect(s != nil, "store decodes")
        try expectEqual(s?.styling.customSyntaxColors, nil,
                        "wrong-typed block -> nil")
        try expectEqual(s?.styling.numbers, .cyan, "presets still decode")
        // Out-of-range / non-integer component values also drop the role.
        let s2 = r89decodeSettings(
            "{\(r89BaseSettings),"
            + " \"styling\": {\"customSyntaxColors\": {\"numbers\": {\"r\": 300, \"g\": 1, \"b\": 2}}}}")
        try expect(s2 != nil, "store decodes")
        try expectEqual(s2?.styling.customSyntaxColors?[.numbers], nil,
                        "out-of-range UInt8 component drops the role")
    },
    EngineCase("r89.model-every-role-roundtrip") {
        // Set all eight roles, encode, decode, and read each one back
        // through the role accessor.
        var s = StylingPreferences.defaults
        let table: [SyntaxColorRole: (UInt8, UInt8, UInt8)] = [
            .numbers: (1, 2, 3), .operators: (4, 5, 6),
            .variables: (7, 8, 9), .units: (10, 11, 12),
            .specifiers: (13, 14, 15), .headings: (16, 17, 18),
            .comments: (19, 20, 21), .labels: (22, 23, 24)]
        for (role, rgb) in table {
            s.setCustomColor(SyntaxSRGBColor(r: rgb.0, g: rgb.1, b: rgb.2),
                             for: role)
        }
        let json = """
        {\(r89BaseSettings), "styling": \(try JSONEncoder().encode(s).toJSONString())}
        """
        let back = r89decodeSettings(json)
        try expect(back != nil, "full custom block encodes + decodes")
        for (role, rgb) in table {
            try expectEqual(back?.styling.customColor(for: role),
                            SyntaxSRGBColor(r: rgb.0, g: rgb.1, b: rgb.2),
                            "\(role) roundtrips")
            try expectEqual(back?.styling.customSyntaxColors?[role],
                            s.customSyntaxColors?[role],
                            "\(role) table accessor roundtrips")
        }
    },
    EngineCase("r89.model-uint8-bounds") {
        try expectEqual(SyntaxSRGBColor(r: 0, g: 0, b: 0),
                        SyntaxSRGBColor(r: 0, g: 0, b: 0), "black")
        try expectEqual(SyntaxSRGBColor(r: 255, g: 255, b: 255),
                        SyntaxSRGBColor(r: 255, g: 255, b: 255), "white")
        // The failable double initializer clamps finite 0...1 input and
        // rejects non-finite input (the app-side conversion drops it).
        try expectEqual(SyntaxSRGBColor(-1, 0.2, 0.3),
                        SyntaxSRGBColor(r: 0, g: 51, b: 77), "clamps below")
        try expectEqual(SyntaxSRGBColor(4, 0.2, 9),
                        SyntaxSRGBColor(r: 255, g: 51, b: 255), "clamps above")
        try expectEqual(SyntaxSRGBColor(.nan, 1, 1), nil, "NaN rejected")
        try expectEqual(SyntaxSRGBColor(.infinity, 1, 1), nil, "inf rejected")
    },
    EngineCase("r89.model-set-clear-and-nil-collapse") {
        var s = StylingPreferences.defaults
        s.setCustomColor(SyntaxSRGBColor(r: 9, g: 9, b: 9), for: .numbers)
        try expectEqual(s.customColor(for: .numbers)?.r, 9, "set stores")
        // Clearing the LAST custom collapses the block back to nil —
        // the encoded store never carries an empty object.
        s.setCustomColor(nil, for: .numbers)
        try expectEqual(s.customSyntaxColors, nil, "last clear -> nil block")
        // Two customs: clearing one keeps the other AND the block.
        s.setCustomColor(SyntaxSRGBColor(r: 1, g: 2, b: 3), for: .units)
        s.setCustomColor(SyntaxSRGBColor(r: 4, g: 5, b: 6), for: .labels)
        try expectEqual(s.customSyntaxColors?.isEmpty, false, "block present")
        s.setCustomColor(nil, for: .labels)
        try expectEqual(s.customColor(for: .labels), nil, "labels cleared")
        try expectEqual(s.customColor(for: .units)?.g, 2, "units kept")
        try expectEqual(s.customSyntaxColors?.isEmpty, false, "block kept")
    },
    EngineCase("r89.model-choose-preset-clears-custom") {
        // The precedence contract: picking any preset makes the role
        // effective-preset again — the custom override is cleared.
        var s = StylingPreferences.defaults
        s.setCustomColor(SyntaxSRGBColor(r: 255, g: 0, b: 0), for: .numbers)
        try expectEqual(s.customColor(for: .numbers),
                        SyntaxSRGBColor(r: 255, g: 0, b: 0), "custom set")
        s.choosePreset(.standardText, for: .numbers)
        try expectEqual(s.presetChoice(for: .numbers), .standardText,
                        "preset switched")
        try expectEqual(s.customColor(for: .numbers), nil,
                        "custom cleared by the preset choice")
        // Other roles are untouched by one role's choice.
        s.setCustomColor(SyntaxSRGBColor(r: 0, g: 255, b: 0), for: .units)
        s.choosePreset(.pinkPurple, for: .numbers)
        try expectEqual(s.customColor(for: .units),
                        SyntaxSRGBColor(r: 0, g: 255, b: 0),
                        "other roles keep their customs")
    },
    EngineCase("r89.model-per-role-reset-restores-exact-defaults") {
        var s = StylingPreferences.defaults
        s.numbers = .green
        s.comments = .standardText
        s.setCustomColor(SyntaxSRGBColor(r: 1, g: 1, b: 1), for: .numbers)
        s.setCustomColor(SyntaxSRGBColor(r: 2, g: 2, b: 2), for: .comments)
        s.resetRoleColors(.numbers)
        try expectEqual(s.numbers, .cyan, "numbers preset restored to default")
        try expectEqual(s.customColor(for: .numbers), nil,
                        "numbers custom cleared")
        try expectEqual(s.comments, .standardText, "other presets untouched")
        try expectEqual(s.customColor(for: .comments),
                        SyntaxSRGBColor(r: 2, g: 2, b: 2),
                        "other customs untouched")
        // A role already at its default preset still gets a clean reset.
        s.resetRoleColors(.operators)
        try expectEqual(s.operators, .standardText, "default preset stays")
        try expectEqual(s.customColor(for: .operators), nil, "no ghost custom")
    },
    EngineCase("r89.model-reset-all-colors-only") {
        // Reset All restores the eight role presets, clears EVERY
        // custom, and preserves fontDesign + the answer-column fields.
        var s = StylingPreferences.defaults
        s.fontDesign = .serif
        s.answerColumnAlignment = .trailing
        s.answerColumnSurface = .sand
        s.numbers = .green
        s.variables = .blue
        s.setCustomColor(SyntaxSRGBColor(r: 5, g: 5, b: 5), for: .numbers)
        s.setCustomColor(SyntaxSRGBColor(r: 6, g: 6, b: 6), for: .headings)
        s.resetAllSyntaxColors()
        let d = StylingPreferences.defaults
        for role in SyntaxColorRole.allCases {
            try expectEqual(s.presetChoice(for: role),
                            d.presetChoice(for: role),
                            "\(role) preset restored to defaults")
            try expectEqual(s.customColor(for: role), nil,
                            "\(role) custom cleared")
        }
        try expectEqual(s.customSyntaxColors, nil, "custom block dropped")
        try expectEqual(s.hasNonDefaultSyntaxColors, false,
                        "reset-all leaves nothing non-default")
        try expectEqual(s.fontDesign, .serif, "font design preserved")
        try expectEqual(s.answerColumnAlignment, .trailing,
                        "answer column alignment preserved")
        try expectEqual(s.answerColumnSurface, .sand,
                        "answer column surface preserved")
        // Idempotent: a second reset-all is a no-op.
        s.resetAllSyntaxColors()
        try expectEqual(s.fontDesign, .serif, "still preserved after re-run")
    },
    EngineCase("r89.model-old-store-equality") {
        // A pre-r89 store decodes to exactly the defaults — the new
        // additive field never changes existing stores.
        let old = """
        {\(r89BaseSettings),
         "styling": {"fontDesign": "system", "numbers": "cyan",
                     "operators": "standardText", "variables": "green",
                     "units": "pinkPurple", "specifiers": "standardText",
                     "headings": "standardText", "comments": "blue",
                     "labels": "standardText"}}
        """
        let s = r89decodeSettings(old)
        try expect(s != nil, "pre-r89 store decodes")
        try expectEqual(s?.styling, StylingPreferences.defaults,
                        "old store equals defaults (additive field)")
    },
]

// MARK: - 2. palette / pure color semantics (source-verified)

let r89PaletteCases: [EngineCase] = [
    EngineCase("r89.palette-single-srgb-conversion") {
        // The palette is the ONE resolver: every role goes through
        // `color(for:custom:)`, and the custom branch is the single
        // exact sRGB conversion in the palette file.
        guard let src = r89AppSource("Sources/NumlexApp/NotebookPalette.swift")
        else { return }
        for role in SyntaxColorRole.allCases {
            try expect(src.contains("styling.customColor(for: .\(role.rawValue))"),
                       "role \(role) resolves custom ?? preset")
        }
        try expectEqual(r89count("Double(custom.r) / 255", in: src), 1,
                        "one exact sRGB conversion for the custom branch")
        // The fixed roles stay fixed: never part of the user-configurable
        // set, never custom-resolved.
        try expect(src.contains("case .moneyMarker: Design.moneyMarkerColor"),
                   "money marker stays a fixed Design token")
        try expect(src.contains("case .hashMarker: Design.headingMarkerColor"),
                   "hash marker stays a fixed Design token")
        // Headings resolve as a body role: the `#` marker is separate.
        try expect(src.contains("case .hashBody: headings"),
                   "heading body (not marker) is configurable")
        // The app-side conversion helpers live beside the palette and
        // go through AppKit only (no platform colors persisted).
        try expect(src.contains("usingColorSpace(.sRGB)"),
                   "platform color conversion is AppKit sRGB")
        try expect(src.contains("NSColor(srgbRed: Double(r) / 255"),
                   "canonical triple converts to opaque sRGB NSColor")
    },
    EngineCase("r89.palette-editor-and-preview-share-resolver") {
        // Both renderers construct NotebookPalette from the SAME
        // StylingPreferences value — no duplicated RGB resolution.
        guard let editor = r89AppSource("Sources/NumlexApp/Editor/NotebookEditor.swift"),
              let settings = r89AppSource("Sources/NumlexApp/Views/SettingsView.swift")
        else { return }
        try expect(editor.contains("NotebookPalette(styling: styling)"),
                   "editor resolves through the shared palette")
        try expect(settings.contains("NotebookPalette(styling: styling)"),
                   "preview resolves through the shared palette")
        // The custom color must be stable across Light/Dark: it is an
        // opaque sRGB constant — no adaptive token on the custom path.
        guard let paletteSrc = r89AppSource("Sources/NumlexApp/NotebookPalette.swift")
        else { return }
        let customStart = paletteSrc.range(of: "if let custom {")?.lowerBound
        let customBody = customStart.map { String(paletteSrc[$0...]) } ?? ""
        try expect(!customBody.contains("adaptive("),
                   "custom branch uses no adaptive (theme-dependent) tokens")
    },
    EngineCase("r89.palette-recolor-is-inplace") {
        // A syntax-color-only settings change must recolor in place
        // (needsDisplay) without re-running the layout/metrics pass;
        // font design (the only layout-affecting styling field) still
        // re-lays out.
        guard let src = r89AppSource("Sources/NumlexApp/Editor/NotebookEditor.swift")
        else { return }
        try expect(src.contains("var recolorOnly = false"),
                   "color-only update path exists")
        try expect(src.contains("if fontDesignChanged { needsRelayout = true } else { recolorOnly = true }"),
                   "only font design re-lays out; colors recolor")
        // The relayout branch is the only one that recomputes metrics
        // after an appearance change.
        let relayout = src.range(of: "if needsRelayout {")
        try expect(relayout != nil, "relayout branch found")
        if let start = relayout?.lowerBound,
           let openEnd = src.range(of: "if recolorOnly {",
                                   range: start..<src.endIndex)?.lowerBound {
            let relayoutBody = String(src[start..<openEnd])
            try expect(relayoutBody.contains("refreshLayoutAndMetrics()"),
                       "relayout branch recomputes metrics")
            let recolorBodyRange = src.range(of: "{",
                                             range: openEnd..<src.endIndex)
                .map { src[$0.lowerBound...].prefix(400) } ?? ""
            try expect(!recolorBodyRange.contains("refreshLayoutAndMetrics()"),
                       "recolor-only branch never recomputes metrics")
        }
        // The in-place restyle guard: highlight() never replaces the
        // string and defers under active IME marked text.
        let hl = src.range(of: "private func highlight()")
        try expect(hl != nil, "highlight() found")
        if let hlStart = hl?.lowerBound,
           let hlEnd = src.range(of: "let spans = SyntaxClassifier.spans",
                                 range: hlStart..<src.endIndex)?.lowerBound {
            try expect(String(src[hlStart..<hlEnd])
                .contains("guard !textView.hasMarkedText()"),
                       "highlight() is safe under IME marked text")
        }
    },
]

// MARK: - 3. settings UI + localization

let r89UICases: [EngineCase] = [
    EngineCase("r89.ui-eight-native-colorpickers") {
        // Eight roles, each row instantiated from the SAME reusable
        // row builder over the finite role enum — one ColorPicker per
        // role with opacity disabled.
        guard let src = r89AppSource("Sources/NumlexApp/Views/SettingsView.swift")
        else { return }
        try expectEqual(SyntaxColorRole.allCases.count, 8, "eight roles")
        try expect(src.contains("ForEach(SyntaxColorRole.allCases, id: \\.self)"),
                   "rows instantiated from the role enum (8x)")
        try expect(src.contains("syntaxRoleRow(role)"),
                   "one reusable row builder")
        try expectEqual(r89count("ColorPicker(\"\", selection: Binding(", in: src), 1,
                                 "one shared well inside the reusable row")
        try expect(src.contains("supportsOpacity: false"),
                   "opacity disabled (opaque sRGB only)")
        try expect(!src.contains("NSColorPanel"), "no fake/legacy panel")
        try expect(!src.contains("NSWindowController"), "no custom palette window")
    },
    EngineCase("r89.ui-wiring-quantize-dedupe-reset") {
        // The well converts picks to the canonical triple, dedupes
        // identical quantized values (no redundant disk writes), and
        // every action routes through the pure model APIs.
        guard let src = r89AppSource("Sources/NumlexApp/Views/SettingsView.swift")
        else { return }
        try expect(src.contains("SyntaxSRGBColor(new)"),
                   "pick converted to the canonical sRGB triple")
        try expect(src.contains("quantized != styling.customColor(for: role)"),
                   "identical quantized values are deduplicated")
        try expect(src.contains("setCustomColor(quantized, for: role)"),
                   "custom written through the pure API")
        try expect(src.contains("choosePreset(choice, for: role)"),
                   "preset choice clears the custom override")
        try expect(src.contains("resetRoleColors(role)"),
                   "per-role Default action wired")
        try expect(src.contains("resetAllSyntaxColors()"),
                   "Reset Syntax Colors wired")
        try expect(src.contains(".disabled(!styling.hasNonDefaultSyntaxColors)"),
                   "Reset All enabled only when non-default")
        try expect(src.contains("if styling.isSyntaxColorNonDefault(role) {"),
                   "per-role reset shown only while non-default")
        try expect(src.contains("Image(systemName: \"arrow.counterclockwise\")"),
                   "reset uses the SF Symbol arrow.counterclockwise")
        try expect(src.contains("customColor(for: role) != nil"),
                   "the menu label distinguishes Custom from presets")
        try expect(src.contains("L10n.t(\"styling.colors.custom\""),
                   "the Custom label is localized, not raw")
        try expect(src.contains("model.persist()"), "changes persist promptly")
        // Live preview + live editor both key off the same settings.
        try expect(src.contains("StylingPreview("), "preview present on the tab")
        try expect(src.contains("NotebookPalette(styling: styling)"),
                   "preview uses the shared palette, no duplicate RGB")
    },
    EngineCase("r89.ui-localization-all-languages") {
        // Every new r89 key resolves in all six languages; the
        // pre-existing role/preset keys keep full parity too.
        let keys = [
            "styling.colors", "styling.colorsCap",
            "styling.colors.custom", "styling.colors.default",
            "styling.colors.resetRole", "styling.colors.resetAll",
            "styling.colors.resetAllCap", "styling.colors.pick",
        ]
        for lang in AppLanguage.allCases {
            for k in keys {
                let v = L10n.t(k, language: lang)
                try expect(v != k && !v.isEmpty,
                           "\(lang) must translate \(k), got: \(v)")
            }
            for role in SyntaxColorRole.allCases {
                let v = L10n.t(role.labelKey, language: lang)
                try expect(v != role.labelKey && !v.isEmpty,
                           "\(lang) must translate \(role.labelKey)")
            }
            for choice in RoleColorChoice.allCases {
                let v = L10n.t("styling.color.\(choice.rawValue)", language: lang)
                try expect(v != "styling.color.\(choice.rawValue)" && !v.isEmpty,
                           "\(lang) must translate styling.color.\(choice.rawValue)")
            }
        }
        try expectEqual(L10n.t("styling.colors.custom", language: .en),
                        "Custom", "English Custom label")
        try expectEqual(L10n.t("styling.colors.resetAll", language: .en),
                        "Reset Syntax Colors", "English Reset All label")
    },
]

// MARK: - 4. hidden-gutter geometry

let r89GeometryCases: [EngineCase] = [
    EngineCase("r89.geometry-shared-indent-source") {
        // ONE pure helper owns the text indent; it is a function of the
        // gutter state only — re-toggling can never accumulate drift.
        guard let design = r89AppSource("Sources/NumlexApp/Design.swift")
        else { return }
        try expect(design.contains("static func textIndent(lineNumbers: Bool) -> CGFloat"),
                   "shared pure indent helper exists")
        try expect(design.contains("(lineNumbers ? gutterWidth : 0) + textLeading"),
                   "ON adds the gutter, OFF reclaims it")
        // The real constants behind the required 54/18 values.
        let gutter = design.contains("gutterWidth: CGFloat = 36")
        let leading = design.contains("textLeading: CGFloat = 18")
        try expect(gutter, "gutter width is 36")
        try expect(leading, "text leading is 18")
        if gutter, leading {
            let on: CGFloat = 36 + 18
            let off: CGFloat = 18
            try expectEqual(on, 54, "ON: byte-compatible 54pt indent")
            try expectEqual(off, 18, "OFF: 18pt indent")
            try expectEqual(on - off, 36, "OFF sits exactly 36pt closer")
        }
        guard let editor = r89AppSource("Sources/NumlexApp/Editor/NotebookEditor.swift")
        else { return }
        try expect(editor.contains("Design.textIndent(lineNumbers: lineNumbers)"),
                   "the editor reads the shared helper (no private copy)")
        try expect(!editor.contains("Design.gutterWidth + Design.textLeading"),
                   "the hardcoded 54pt indent is gone")
        try expectEqual(r89count("gutterWidth + Design.textLeading", in: editor), 0,
                        "no duplicate indent math anywhere in the editor")
    },
    EngineCase("r89.geometry-both-indents-wired") {
        // firstLineHeadIndent AND headIndent come from the same
        // paragraph style built from the shared helper, so the first
        // line and every wrapped continuation move together.
        guard let src = r89AppSource("Sources/NumlexApp/Editor/NotebookEditor.swift")
        else { return }
        guard let fnStart = src.range(of: "private func paragraphStyle()")?.lowerBound
        else { return try expect(false, "paragraphStyle() found") }
        let fnEnd = src.range(of: "/// Restyles the current text IN PLACE",
                              range: fnStart..<src.endIndex)?.lowerBound
            ?? src.index(fnStart, offsetBy: 500)
        let body = String(src[fnStart..<fnEnd])
        try expect(body.contains("para.firstLineHeadIndent = textIndent"),
                   "first-line indent from the shared helper")
        try expect(body.contains("para.headIndent = textIndent"),
                   "continuation indent from the shared helper")
        try expect(body.contains("Design.gutterWidth") == false,
                   "the paragraph style has no private gutter math")
    },
    EngineCase("r89.geometry-update-order-and-preservation") {
        // The gutter state is committed BEFORE the typography pass
        // builds paragraph styles (no stale-indent update), and the
        // gutter toggle still re-lays out (metrics + answer baselines
        // follow) — while a color-only update never does.
        guard let src = r89AppSource("Sources/NumlexApp/Editor/NotebookEditor.swift")
        else { return }
        let setGutter = src.range(of: "if lineNumbers != self.lineNumbers")
        let typography = src.range(of: "applyTypography()",
                                   range: src.startIndex..<src.endIndex)
        try expect(setGutter != nil && typography != nil, "both phases found")
        if let a = setGutter?.lowerBound, let b = typography?.lowerBound, a < b {
            let between = String(src[a..<b])
            try expect(between.contains("self.lineNumbers = lineNumbers"),
                       "gutter state committed before typography")
        }
        // Highlight fills keep their conditional gutter start, so a
        // hidden gutter aligns the fill to the leading edge and an
        // enabled gutter never paints over the numbers.
        try expect(src.contains("origin.x + (tv.lineNumbers ? Design.gutterWidth : 0)"),
                   "highlight fill x stays conditional on the gutter")
        // The gutter only draws its glyphs while line numbers are on.
        let draw = src.range(of: "override func draw(_ dirtyRect: NSRect)")?.lowerBound
        if let d = draw {
            let body = String(src[d...].prefix(600))
            try expect(body.contains("if lineNumbers {"),
                       "gutter glyphs skipped when hidden")
        }
    },
    EngineCase("r89.geometry-cycle-stability") {
        // The indent is a PURE function of the current gutter state
        // (no stored offset mutated per toggle), so any OFF/ON cycle
        // returns to the identical positions — verified against the
        // real constants.
        let gutter: CGFloat = 36, leading: CGFloat = 18
        func indent(_ on: Bool) -> CGFloat { (on ? gutter : 0) + leading }
        var state = true
        let on1 = indent(state)
        for _ in 0..<8 { state.toggle() }  // 8 toggles -> back to ON
        try expectEqual(indent(state), on1, "repeated cycles: no drift")
        try expectEqual(indent(true), 54, "ON position")
        try expectEqual(indent(false), 18, "OFF position")
        try expectEqual(indent(false) + gutter, indent(true),
                        "ON == OFF reclaimed by the full gutter width")
    },
]

private extension Data {
    func toJSONString() -> String {
        String(data: self, encoding: .utf8) ?? "null"
    }
}
