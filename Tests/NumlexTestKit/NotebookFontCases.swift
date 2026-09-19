import Foundation
import NumlexCore

/// r90: installed notebook font selection.
///
/// The model side is pure and portable: `StylingPreferences` persists an
/// optional installed `fontFamily`/`fontFace` next to the unchanged
/// built-in `fontDesign`, decoding is key-by-key tolerant, and the three
/// selection helpers enforce the clearing rules. The app side is pinned
/// by source-contract cases: ONE shared installed-font catalog feeds the
/// Settings menus, the notebook resolver and the export dialog, every
/// notebook surface receives the SAME full styling and effective line
/// height, and a typography change relayouts while a color-only change
/// does not.

private func nfDecode(_ json: String) -> StylingPreferences? {
    guard let data = json.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(StylingPreferences.self, from: data)
}

private func nfEncode(_ value: StylingPreferences) -> String {
    guard let data = try? JSONEncoder().encode(value) else { return "" }
    return String(data: data, encoding: .utf8) ?? ""
}

/// The repo-relative source text, or nil when the file is missing (the
/// case then reports a loud failure instead of passing silently).
private func nfSource(_ rel: String) -> String? {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // NumlexTestKit
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repo root
    let url = root.appendingPathComponent(rel).standardizedFileURL
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try? String(contentsOf: url, encoding: .utf8)
}

private func nfRequire(_ rel: String) throws -> String {
    guard let src = nfSource(rel) else {
        throw CaseFailure(message: "missing source \(rel)", location: "NotebookFontCases")
    }
    return src
}

private func nfCount(_ needle: String, in haystack: String) -> Int {
    guard !needle.isEmpty else { return 0 }
    var count = 0
    var rest = Substring(haystack)
    while let r = rest.range(of: needle) {
        count += 1
        rest = rest[r.upperBound...]
    }
    return count
}

public let notebookFontCases: [EngineCase] = [

    // MARK: - Model: defaults and tolerant decoding

    EngineCase("r90-font-defaults-are-system-and-empty") {
        let d = StylingPreferences.defaults
        try expectEqual(d.fontDesign, .system, "default design")
        try expect(d.fontFamily == nil, "default family is nil")
        try expect(d.fontFace == nil, "default face is nil")
        try expect(!d.hasCustomFont, "no custom font by default")
        // A default instance must NOT carry the new keys, so existing
        // stores keep their exact byte shape.
        let encoded = nfEncode(d)
        try expect(!encoded.contains("fontFamily"), "default omits fontFamily")
        try expect(!encoded.contains("fontFace"), "default omits fontFace")
        try expect(encoded.contains("\"fontDesign\":\"system\""), "design still encoded")
    },

    EngineCase("r90-font-old-and-partial-payloads-decode") {
        // A pre-r90 payload (no family/face keys at all).
        let old = nfDecode("{\"fontDesign\":\"rounded\"}")
        try expectEqual(old?.fontDesign, .rounded, "old design preserved")
        try expect(old?.fontFamily == nil, "old payload family nil")
        try expect(old?.fontFace == nil, "old payload face nil")
        // A completely empty styling object.
        let empty = nfDecode("{}")
        try expectEqual(empty?.fontDesign, .system, "empty -> system")
        try expect(empty?.fontFamily == nil && empty?.fontFace == nil, "empty -> nil/nil")
        // A partial payload with only a family.
        let partial = nfDecode("{\"fontFamily\":\"Menlo\"}")
        try expectEqual(partial?.fontFamily, "Menlo", "partial family kept")
        try expect(partial?.fontFace == nil, "partial face nil")
        // Unrelated fields keep decoding exactly as before.
        let mixed = nfDecode("{\"fontDesign\":\"serif\",\"numbers\":\"green\",\"answerColumnWidth\":333}")
        try expectEqual(mixed?.fontDesign, .serif, "design")
        try expectEqual(mixed?.numbers, .green, "numbers")
        try expectEqual(mixed?.answerColumnWidth, 333, "width")
    },

    EngineCase("r90-font-valid-values-round-trip") {
        var value = StylingPreferences.defaults
        value.chooseFontFamily("Helvetica Neue")
        value.chooseFontFace("HelveticaNeue-Bold")
        try expectEqual(value.fontFamily, "Helvetica Neue", "family stored")
        try expectEqual(value.fontFace, "HelveticaNeue-Bold", "face stored")
        try expect(value.hasCustomFont, "custom font flagged")
        let restored = nfDecode(nfEncode(value))
        try expectEqual(restored, value, "exact round-trip")
        // The design is retained as the fallback alongside the family.
        try expectEqual(restored?.fontDesign, .system, "fallback design kept")
        // A face with no family is impossible through the public API.
        var noFace = StylingPreferences.defaults
        noFace.chooseFontFamily("Menlo")
        try expectEqual(noFace.fontFace, nil, "family selection clears the face")
    },

    EngineCase("r90-font-malformed-values-drop-their-own-field") {
        // Invalid family: the family AND its dependent face both drop.
        let badFamilies = ["42", "\"\"", "\"   \\n \"", "\"Hel\\u0007vetica\"",
                           "\"\(String(repeating: "a", count: 257))\"", "[1,2]", "null"]
        for raw in badFamilies {
            let value = nfDecode("{\"fontFamily\":\(raw),\"fontFace\":\"Helvetica-Bold\"}")
            try expect(value != nil, "payload still decodes: \(raw)")
            try expect(value?.fontFamily == nil, "invalid family dropped: \(raw)")
            try expect(value?.fontFace == nil, "face cannot survive a bad family: \(raw)")
            try expectEqual(value?.fontDesign, .system, "design fallback: \(raw)")
        }
        // Invalid face: only the face drops, the family survives.
        let badFaces = ["\"  \"", "42", "[1]", "\"Bad\\u0000Face\"",
                        "\"\(String(repeating: "b", count: 300))\"", "null"]
        for raw in badFaces {
            let value = nfDecode("{\"fontFamily\":\"Helvetica\",\"fontFace\":\(raw)}")
            try expectEqual(value?.fontFamily, "Helvetica", "family kept: \(raw)")
            try expect(value?.fontFace == nil, "invalid face dropped: \(raw)")
        }
        // Boundary: exactly 256 scalars is accepted, 257 is not.
        let at256 = String(repeating: "a", count: 256)
        try expectEqual(nfDecode("{\"fontFamily\":\"\(at256)\"}")?.fontFamily, at256,
                        "256 scalars accepted")
        let at257 = String(repeating: "a", count: 257)
        try expect(nfDecode("{\"fontFamily\":\"\(at257)\"}")?.fontFamily == nil,
                   "257 scalars rejected")
        // Surrounding whitespace/newlines are trimmed, not rejected.
        let padded = nfDecode("{\"fontFamily\":\"  Helvetica  \",\"fontFace\":\" Helvetica-Bold \"}")
        try expectEqual(padded?.fontFamily, "Helvetica", "family trimmed")
        try expectEqual(padded?.fontFace, "Helvetica-Bold", "face trimmed")
        // The sanitizer itself.
        try expectEqual(StylingFontName.sanitize("  Menlo  "), "Menlo", "sanitize trims")
        try expect(StylingFontName.sanitize(nil) == nil, "nil stays nil")
        try expect(StylingFontName.sanitize("") == nil, "empty rejected")
        try expect(StylingFontName.sanitize("\n\t ") == nil, "whitespace rejected")
        try expect(StylingFontName.sanitize("a\u{0000}b") == nil, "control rejected")
        try expect(StylingFontName.sanitize("a\nb") == nil, "newline rejected")
        try expectEqual(StylingFontName.maxScalars, 256, "documented ceiling")
    },

    EngineCase("r90-font-face-without-family-is-dropped") {
        // A persisted face with no family is meaningless: the decoder
        // drops it rather than letting a later family choice inherit it.
        let orphan = nfDecode("{\"fontFace\":\"Helvetica-Bold\"}")
        try expect(orphan?.fontFamily == nil, "no family")
        try expect(orphan?.fontFace == nil, "orphan face dropped")
        // The memberwise initializer applies the same rule.
        let built = StylingPreferences(fontDesign: .serif, fontFamily: nil,
                                       fontFace: "Helvetica-Bold")
        try expect(built.fontFamily == nil && built.fontFace == nil, "init drops the face")
        let blankFamily = StylingPreferences(fontDesign: .rounded, fontFamily: "   ",
                                            fontFace: "Helvetica-Bold")
        try expect(blankFamily.fontFamily == nil && blankFamily.fontFace == nil,
                   "blank family drops both")
        try expectEqual(blankFamily.fontDesign, .rounded, "design retained")
        let trimmed = StylingPreferences(fontFamily: " Helvetica ", fontFace: " Helvetica-Bold ")
        try expectEqual(trimmed.fontFamily, "Helvetica", "init trims the family")
        try expectEqual(trimmed.fontFace, "Helvetica-Bold", "init trims the face")
    },

    EngineCase("r90-font-selection-helpers-clearing-rules") {
        var value = StylingPreferences.defaults
        // Choosing a built-in design clears the installed selection.
        value.chooseFontFamily("Menlo")
        value.chooseFontFace("Menlo-Bold")
        value.chooseBuiltInDesign(.monospaced)
        try expectEqual(value.fontDesign, .monospaced, "design set")
        try expect(value.fontFamily == nil && value.fontFace == nil, "built-in clears custom")
        // Choosing a family clears the previous family's face.
        value.chooseFontFamily("Georgia")
        value.chooseFontFace("Georgia-Bold")
        value.chooseFontFamily("Courier New")
        try expectEqual(value.fontFamily, "Courier New", "new family stored")
        try expect(value.fontFace == nil, "old face cleared with the family")
        try expectEqual(value.fontDesign, .monospaced, "fallback design untouched")
        // Choosing a face requires a family.
        value.chooseFontFace("CourierNewPS-BoldMT")
        try expectEqual(value.fontFace, "CourierNewPS-BoldMT", "face stored with a family")
        value.chooseBuiltInDesign(.system)
        value.chooseFontFace("Orphan-Face")
        try expect(value.fontFace == nil, "face without a family is refused")
        // An unusable family name clears instead of persisting garbage.
        value.chooseFontFamily("Helvetica")
        value.chooseFontFamily("   ")
        try expect(value.fontFamily == nil && value.fontFace == nil, "blank family clears")
        value.chooseFontFamily("Helvetica\u{0007}")
        try expect(value.fontFamily == nil, "control-char family clears")
        // nil face = the catalog's deterministic regular face.
        value.chooseFontFamily("Menlo")
        value.chooseFontFace("Menlo-Bold")
        value.chooseFontFace(nil)
        try expectEqual(value.fontFamily, "Menlo", "family kept")
        try expect(value.fontFace == nil, "nil face restores regular")
    },

    EngineCase("r90-font-design-raw-values-and-fallback-unchanged") {
        try expectEqual(StylingFontDesign.allCases.map(\.rawValue),
                        ["system", "rounded", "serif", "monospaced"], "raw values frozen")
        for design in StylingFontDesign.allCases {
            let decoded = nfDecode("{\"fontDesign\":\"\(design.rawValue)\"}")
            try expectEqual(decoded?.fontDesign, design, "\(design.rawValue) decodes")
            try expect(decoded?.fontFamily == nil, "no family invented")
        }
        // An unknown design still falls back instead of failing the store.
        try expectEqual(nfDecode("{\"fontDesign\":\"comic\"}")?.fontDesign, .system,
                        "unknown design falls back")
    },

    EngineCase("r90-font-color-reset-preserves-typography") {
        var value = StylingPreferences.defaults
        value.chooseFontFamily("Helvetica")
        value.chooseFontFace("Helvetica-Bold")
        value.answerColumnWidth = 321
        value.answerColumnAlignment = .trailing
        value.choosePreset(.pinkPurple, for: .numbers)
        value.setCustomColor(SyntaxSRGBColor(r: 1, g: 2, b: 3), for: .units)
        value.resetAllSyntaxColors()
        try expectEqual(value.fontFamily, "Helvetica", "family survives a color reset")
        try expectEqual(value.fontFace, "Helvetica-Bold", "face survives a color reset")
        try expectEqual(value.fontDesign, .system, "design survives")
        try expectEqual(value.answerColumnWidth, 321, "width survives")
        try expectEqual(value.answerColumnAlignment, .trailing, "alignment survives")
        try expectEqual(value.numbers, .cyan, "preset restored")
        try expect(value.customSyntaxColors == nil, "custom colors dropped")
        // The per-role reset is equally typography-safe.
        value.choosePreset(.green, for: .comments)
        value.resetRoleColors(.comments)
        try expectEqual(value.fontFamily, "Helvetica", "per-role reset keeps typography")
        try expectEqual(value.fontFace, "Helvetica-Bold", "per-role reset keeps the face")
    },

    // MARK: - App: one shared catalog

    EngineCase("r91-font-catalog-rejects-hidden-and-faceless-families") {
        // Synthetic input covering every rejection rule at once: an empty
        // name, a whitespace-only name, a control character, a HIDDEN
        // dot-prefixed name, a face-less family, and case-folded
        // duplicates.
        let raw = ["", "   ", "Bad\u{0007}Name", ".AppleSystemUIFont",
                   ".SF NS", "Ghost", "Zed", "alpha", "Alpha"]
        let members: [String: [[String]]] = [
            ".AppleSystemUIFont": [["AppleSystemUIFont", "Regular"]],
            ".SF NS": [["SFNS-Regular", "Regular"]],
            "Ghost": [],
            "Zed": [["Zed-Bold", "Bold"], ["Zed", "Regular"], ["Zed", "Regular"]],
            "alpha": [["Alpha-Roman", "Roman"]],
            "Alpha": [["AlphaOther-Regular", "Regular"]],
        ]
        let families = InstalledFontNames.families(raw) { members[$0] ?? [] }
        let names = families.map(\.name)
        try expectEqual(names, ["alpha", "Zed"], "hidden/faceless/empty/control dropped")
        try expect(!names.contains(".AppleSystemUIFont"), "dot-prefixed hidden family dropped")
        try expect(!names.contains(".SF NS"), "spaced hidden family dropped")
        try expect(!names.contains("Ghost"), "face-less family dropped")
        try expect(!names.contains(where: { $0.contains("\u{0007}") }), "control dropped")
        try expect(!names.contains(""), "empty dropped")
        try expectEqual(names.filter { $0.lowercased() == "alpha" }.count, 1,
                        "case-folded duplicate collapsed")
        try expectEqual(names.first, "alpha", "first spelling kept")
        // A face-less family is absent from BOTH enumeration and faces.
        try expect(!names.contains("Ghost"), "face-less family not enumerated")
        try expect(InstalledFontNames.families(["Ghost"]) { _ in [] }.isEmpty,
                   "a lone face-less family yields no families")
        // Faces stay deduplicated and regular-preferring.
        let zed = families.first { $0.name == "Zed" }
        try expectEqual(zed?.faces.map(\.label), ["Regular", "Bold"], "regular first, deduped")
        try expectEqual(zed?.faces.map(\.name), ["Zed", "Zed-Bold"], "PostScript names kept")
        try expectEqual(families.first { $0.name == "alpha" }?.faces.map(\.label), ["Roman"],
                        "Roman ranks as regular")
        // The rules themselves.
        try expect(InstalledFontNames.isHidden(".Hidden"), "dot prefix hidden")
        try expect(InstalledFontNames.isHidden("  .Hidden  "), "trimmed dot prefix hidden")
        try expect(!InstalledFontNames.isHidden("Visible"), "normal name visible")
        try expect(!InstalledFontNames.isHidden("mid.dot"), "inner dot is not hidden")
        try expect(InstalledFontNames.usableName("  ") == nil, "whitespace unusable")
        try expect(InstalledFontNames.usableName("a\u{0000}b") == nil, "control unusable")
        try expectEqual(InstalledFontNames.usableName("  Menlo  "), "Menlo", "trims")
        for token in ["Regular", "Roman", "Book", "Normal", "REGULAR", "book italic"] {
            try expectEqual(InstalledFontNames.regularRank(token), 0, "\(token) ranks regular")
        }
        for token in ["Bold", "Italic", "Light"] {
            try expectEqual(InstalledFontNames.regularRank(token), 1, "\(token) does not")
        }
        // Malformed member rows are skipped, never crash.
        let malformed = InstalledFontNames.faces(fromMembers: [["OnlyName"], [], ["", "Empty"],
                                                              ["Ok-Regular", "Regular"]])
        try expectEqual(malformed.map(\.name), ["Ok-Regular"], "malformed rows skipped")
    },

    EngineCase("r91-font-catalog-delegates-to-the-pure-rules") {
        let catalog = try nfRequire("Sources/NumlexApp/InstalledFontCatalog.swift")
        try expect(catalog.contains("InstalledFontNames.families("),
                   "families come from the pure core rules")
        try expect(catalog.contains("InstalledFontNames.regularRank("),
                   "regular preference delegated")
        try expect(catalog.contains("InstalledFontNames.isHidden("),
                   "hidden-name rule delegated")
        // The rules live in the dependency-free core (no AppKit there).
        let rules = try nfRequire("Sources/NumlexCore/Models/InstalledFontNames.swift")
        try expect(!rules.contains("import AppKit"), "core rules stay dependency-free")
        try expect(rules.contains("public static func isHidden"), "hidden rule present")
        try expect(rules.contains("guard !faces.isEmpty else { continue }"),
                   "face-less families omitted")
        try expect(rules.contains("hasPrefix(\".\")"), "dot-prefix rejection present")
        // Membership and faces agree by construction: one table.
        try expect(catalog.contains("facesByFamily = Dictionary(uniqueKeysWithValues:"),
                   "one table backs families/faces/membership")
        try expect(catalog.contains("guard let family, contains(family: family) else { return fallback() }"),
                   "resolution honours membership")
    },

    EngineCase("r90-font-one-shared-installed-catalog") {
        let catalog = try nfRequire("Sources/NumlexApp/InstalledFontCatalog.swift")
        try expect(catalog.contains("static let shared = InstalledFontCatalog()"),
                   "one shared instance")
        try expect(catalog.contains("NSFontManager.shared.availableFontFamilies"),
                   "families come from the font manager")
        try expect(catalog.contains("availableMembers(ofFontFamily:"),
                   "faces come from the font manager")
        // r91: ordering/name rules live in the pure core rules; the app
        // type delegates and owns only the AppKit adaptation.
        let rules = try nfRequire("Sources/NumlexCore/Models/InstalledFontNames.swift")
        try expect(rules.contains("localizedCaseInsensitiveCompare"),
                   "localized case-insensitive order")
        try expect(rules.contains("regularRank"),
                   "deterministic regular preference")
        for token in ["regular", "roman", "book", "normal"] {
            try expect(rules.lowercased().contains("\"\(token)\""),
                       "regular preference covers \(token)")
        }
        try expect(rules.contains("ControlCharacters") || rules.contains("controlCharacters"),
                   "control-character names rejected")
        try expect(catalog.contains("InstalledFontNames.families("),
                   "the app catalog uses the pure rules")
        try expect(catalog.contains("contains(family:"),
                   "family membership check")
        try expect(catalog.contains("boldVariant"), "bold derivation")
        try expect(catalog.contains("familyName == base.familyName"),
                   "derived weight never changes family")
        // The export catalog delegates instead of enumerating again.
        let export = try nfRequire("Sources/NumlexApp/Export/ExportFontCatalog.swift")
        try expect(!export.contains("availableFontFamilies"),
                   "export does not re-enumerate families")
        try expect(!export.contains("availableMembers"),
                   "export does not re-enumerate faces")
        try expect(export.contains("InstalledFontCatalog.shared.families"),
                   "export uses the shared families")
        try expect(export.contains("InstalledFontCatalog.shared.faces(for: family)"),
                   "export uses the shared faces")
        try expect(export.contains("InstalledFontCatalog.shared.font("),
                   "export resolves through the shared catalog")
        // Exactly one enumeration of installed families in the whole app.
        let dialog = try nfRequire("Sources/NumlexApp/Export/ExportDialogView.swift")
        try expect(dialog.contains("ExportFontCatalog.shared.families")
                   && dialog.contains("ExportFontCatalog.shared.faces(for:"),
                   "dialog reads the shared catalog")
        try expect(!dialog.contains("availableFontFamilies"),
                   "dialog never enumerates fonts itself")
    },

    EngineCase("r90-font-palette-resolves-through-the-catalog") {
        let palette = try nfRequire("Sources/NumlexApp/NotebookPalette.swift")
        try expect(palette.contains("let styling: StylingPreferences"),
                   "palette carries the full selection")
        try expect(palette.contains("InstalledFontCatalog.shared.font("),
                   "resolution goes through the shared catalog")
        try expect(palette.contains("guard let family = styling.fontFamily else { return base }"),
                   "nil family keeps the system design path")
        try expect(palette.contains("systemDesignFont"),
                   "system-design fallback exists")
        try expect(palette.contains("Font.custom(font.fontName, fixedSize: size)"),
                   "SwiftUI uses the exact PostScript face at fixed size")
        try expect(!palette.contains("Font.system(size:"),
                   "no re-resolved SwiftUI design remains")
        try expect(palette.contains("func semiboldFont") && palette.contains("func heavyFont"),
                   "semibold/heavy companions")
        try expect(palette.contains("effectiveLineHeight"),
                   "effective line height helper")
        try expect(palette.contains("(tallest + 4).rounded(.up)"),
                   "natural metrics + 4 pt, rounded up")
        try expect(palette.contains("max(requested,"),
                   "requested height stays the floor")
        try expect(palette.contains("guard styling.fontFamily != nil else { return requested }"),
                   "system designs keep the requested height exactly")
    },

    // MARK: - App: settings controls and localization

    EngineCase("r90-font-settings-controls-and-one-persist") {
        let settings = try nfRequire("Sources/NumlexApp/Views/SettingsView.swift")
        // Built-in designs stay directly in the Font menu.
        try expect(settings.contains("ForEach(StylingFontDesign.allCases, id: \\.self)"),
                   "built-in designs listed")
        try expect(settings.contains("L10n.t(\"styling.font.installed\""),
                   "installed-fonts submenu")
        try expect(settings.contains("ForEach(fontCatalog.families, id: \\.self)"),
                   "every installed family listed")
        // The Face row is conditional on a custom family.
        try expect(settings.contains("if let family = styling.fontFamily {"),
                   "face row only for a custom family")
        try expect(settings.contains("ForEach(fontCatalog.faces(for: family))"),
                   "faces of that family listed")
        try expect(settings.contains("L10n.t(\"styling.font.face.regular\""),
                   "Regular maps to nil")
        // Exactly one persist per user choice.
        for handler in ["private func chooseDesign", "private func chooseFamily",
                        "private func chooseFace"] {
            guard let start = settings.range(of: handler)?.lowerBound,
                  let end = settings.range(of: "\n    }", range: start..<settings.endIndex)?
                    .lowerBound else {
                throw CaseFailure(message: "missing \(handler)", location: "NotebookFontCases")
            }
            let body = String(settings[start..<end])
            try expectEqual(nfCount("model.persist()", in: body), 1,
                            "exactly one persist in \(handler)")
            try expect(body.contains("model.settings.styling."),
                       "\(handler) mutates styling through the model")
        }
        // The three handlers are the only mutation paths from the menus.
        try expectEqual(nfCount("model.settings.styling.fontDesign =", in: settings), 0,
                        "no direct design assignment remains")
        try expectEqual(nfCount("model.settings.styling.chooseBuiltInDesign(", in: settings), 1,
                        "the built-in helper is the only design mutation")
        try expectEqual(nfCount("model.settings.styling.chooseFontFamily(", in: settings), 1,
                        "the family helper is the only family mutation")
        try expectEqual(nfCount("model.settings.styling.chooseFontFace(", in: settings), 1,
                        "the face helper is the only face mutation")
        // Unavailable values stay representable and are signalled.
        try expect(settings.contains("familyUnavailable") && settings.contains("faceUnavailable"),
                   "unavailable detection")
        try expect(settings.contains("L10n.t(\"styling.font.unavailable\""),
                   "localized unavailable marker")
        try expect(settings.contains("L10n.t(\"styling.font.unavailableCap\""),
                   "localized unavailable explanation")
        // Long names cannot enlarge the window.
        try expectEqual(nfCount(".frame(maxWidth: 160, alignment: .trailing)", in: settings) >= 3,
                        true, "labels capped at 160 pt")
        try expect(settings.contains(".truncationMode(.middle)"),
                   "long names truncate in the middle")
        try expect(settings.contains(".lineLimit(1)"), "labels stay one line")
    },

    EngineCase("r90-font-localization-all-six-languages") {
        let keys = ["styling.font.installed", "styling.font.face",
                    "styling.font.face.regular", "styling.font.unavailable",
                    "styling.font.unavailableCap"]
        try expectEqual(AppLanguage.allCases.count, 6, "six app languages")
        for language in AppLanguage.allCases {
            for key in keys {
                let value = L10n.t(key, language: language)
                try expect(value != key, "\(language.rawValue) missing \(key)")
                try expect(!value.trimmingCharacters(in: .whitespaces).isEmpty,
                           "\(language.rawValue) empty \(key)")
            }
        }
        // The four built-in design labels are unchanged in every language.
        for language in AppLanguage.allCases {
            for design in StylingFontDesign.allCases {
                let key = "styling.font.\(design.rawValue)"
                try expect(L10n.t(key, language: language) != key,
                           "\(language.rawValue) missing \(key)")
            }
        }
        // Every key exists in the source table six times (one per locale).
        let source = try nfRequire("Sources/NumlexCore/Localization.swift")
        for key in keys {
            try expectEqual(nfCount("\"\(key)\"", in: source), 6, "six entries for \(key)")
        }
    },

    // MARK: - App: surfaces share one typography value

    EngineCase("r90-font-surfaces-share-styling-and-line-height") {
        let content = try nfRequire("Sources/NumlexApp/Views/ContentView.swift")
        // ONE computed effective line height feeding both surfaces.
        try expect(content.contains("NotebookPalette.effectiveLineHeight(styling: settings.styling"),
                   "effective height computed from the full styling")
        try expectEqual(nfCount("lineHeight: effectiveLineHeight(settings)", in: content), 2,
                        "editor and answer column share the value")
        try expectEqual(nfCount("styling: settings.styling", in: content) >= 2, true,
                        "both surfaces receive the full styling")
        try expect(!content.contains("fontDesign: settings.styling.fontDesign"),
                   "no design-only reconstruction")
        // The answer column takes full styling and builds its palette from it.
        let answer = try nfRequire("Sources/NumlexApp/Views/AnswerColumnView.swift")
        try expect(answer.contains("var styling: StylingPreferences"),
                   "answer column takes full styling")
        try expect(!answer.contains("var fontDesign:"), "design-only input removed")
        try expect(answer.contains("NotebookPalette(styling: styling)"),
                   "palette from the exact value")
        // The preview uses the same helper.
        let settings = try nfRequire("Sources/NumlexApp/Views/SettingsView.swift")
        try expect(settings.contains("NotebookPalette.effectiveLineHeight("),
                   "preview uses the shared helper")
        try expect(settings.contains("lineHeight: NotebookPalette.effectiveLineHeight("),
                   "preview passes the effective height")
        // The editor resolves through the palette (no raw system font).
        let editor = try nfRequire("Sources/NumlexApp/Editor/NotebookEditor.swift")
        try expect(editor.contains("private var palette: NotebookPalette { NotebookPalette(styling: styling) }"),
                   "editor palette from the full styling")
        try expect(!editor.contains("Font.system(size:"),
                   "editor does not build SwiftUI system fonts")
        // Footer width uses the resolved font.
        try expect(answer.contains("let valueWidth = Self.measuredWidth(value, font: palette.editorFont(size: fontSize))"),
                   "footer width uses the resolved font")
    },

    EngineCase("r90-font-relayout-on-typography-only") {
        let editor = try nfRequire("Sources/NumlexApp/Editor/NotebookEditor.swift")
        try expect(editor.contains("let typographyChanged = self.styling.fontDesign != styling.fontDesign"),
                   "design is a typography change")
        try expect(editor.contains("|| self.styling.fontFamily != styling.fontFamily"),
                   "family is a typography change")
        try expect(editor.contains("|| self.styling.fontFace != styling.fontFace"),
                   "face is a typography change")
        try expect(editor.contains("if typographyChanged { needsRelayout = true } else { recolorOnly = true }"),
                   "typography relayouts, colors recolor")
        // The relayout branch still owns the metrics refresh, and the
        // color branch never touches it.
        guard let relayout = editor.range(of: "if needsRelayout {")?.lowerBound,
              let recolor = editor.range(of: "if recolorOnly {",
                                         range: relayout..<editor.endIndex)?.lowerBound else {
            throw CaseFailure(message: "relayout/recolor branches missing",
                              location: "NotebookFontCases")
        }
        let relayoutBody = String(editor[relayout..<recolor])
        try expect(relayoutBody.contains("refreshLayoutAndMetrics()"),
                   "relayout refreshes metrics")
        try expect(!relayoutBody.contains("string = "), "relayout never rewrites the text")
        try expect(!relayoutBody.contains("model."), "relayout never touches the model")
    },

    // MARK: - App: export inheritance

    EngineCase("r90-font-export-notebook-inherits-custom-font") {
        let export = try nfRequire("Sources/NumlexApp/Export/ExportFontCatalog.swift")
        try expect(export.contains("NotebookPalette(styling: styling).editorFont(size: size)"),
                   "the notebook font resolves the custom selection")
        try expect(export.contains("guard let family, families.contains(family) else { return notebook }"),
                   "nil/unknown export family falls back to the notebook font")
        try expect(export.contains("InstalledFontCatalog.shared.font(family: family, face: face"),
                   "explicit export faces resolve through the shared catalog")
        // Export options stay session-only: the dialog never persists.
        let dialog = try nfRequire("Sources/NumlexApp/Export/ExportDialogView.swift")
        try expect(!dialog.contains("persist()"), "export dialog never persists")
        try expect(dialog.contains("options.fontFace = nil"),
                   "a new export family clears the export face")
        let types = try nfRequire("Sources/NumlexCore/Export/ExportTypes.swift")
        try expect(types.contains("public var fontFamily: String?"),
                   "export family stays session-only state")
    },
]
