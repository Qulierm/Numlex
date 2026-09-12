import Foundation
import NumlexCore

// MARK: - temporal Task 1: Dates & Times settings / custom timezones

private func tzSettingsRepoRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func tzSettingsSource(_ rel: String) -> String {
    let url = tzSettingsRepoRoot().appendingPathComponent(rel).standardizedFileURL
    return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
}

/// Injected now: 2024-06-15 12:00 Paris (CEST, UTC+2) -> 10:00 UTC.
private func tzSettingsNow() -> (Date, Calendar) {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Europe/Paris")!
    let date = cal.date(from: DateComponents(year: 2024, month: 6, day: 15,
                                             hour: 12, minute: 0))!
    return (date, cal)
}

private func tzSettingsEval(_ line: String,
                            preferences: TemporalPreferences) -> LineResult? {
    let (now, cal) = tzSettingsNow()
    var v: [String: Double] = [:]
    return evalLine(line, variables: &v, rates: Rates(), decimalPlaces: 10,
                    now: now, calendar: cal, context: .legacy,
                    unitContext: .builtIns, preferences: preferences)
}

private func tzSettingsText(_ line: String,
                            preferences: TemporalPreferences) -> String? {
    guard let r = tzSettingsEval(line, preferences: preferences) else { return nil }
    return AnswerDisplay.displayText(for: r, decimalPlaces: 10, context: .legacy)
}

private let tzSettingsKeys = [
    "settings.datesTimes", "settings.datesTimesShort",
    "timezones.group", "timezones.intro", "timezones.add",
    "timezones.name", "timezones.identifier", "timezones.delete",
    "timezones.emptyTitle", "timezones.emptyCap",
    "timezones.status.active", "timezones.status.incomplete",
    "timezones.status.invalidName", "timezones.status.duplicate",
    "timezones.status.builtInCollision", "timezones.status.unknownZone",
]

public let timezoneSettingsCases: [EngineCase] = [

    EngineCase("timezone-settings-validation-matrix") {
        let catalog = TimezoneCatalog.shared
        try expect(catalog != nil, "the bundled catalog loads")

        func state(_ name: String, _ id: String,
                   zones: [CustomTimeZone] = []) -> CustomTimeZoneState {
            CustomTimeZoneEditor.state(name: name, identifier: id,
                                       zones: zones, catalog: catalog)
        }
        // Both fields empty is a quiet fresh row, not an error.
        try expectEqual(state("", ""), .empty, "both empty")
        try expectEqual(state("   ", "  "), .empty, "whitespace is empty")
        // Exactly one field filled is incomplete.
        try expectEqual(state("Office", ""), .incomplete, "name only")
        try expectEqual(state("", "Europe/Paris"), .incomplete, "identifier only")
        // Name-shape failures.
        try expectEqual(state("123", "Europe/Paris"), .invalidName, "starts with a digit")
        try expectEqual(state("Paris!", "Europe/Paris"), .invalidName, "punctuation")
        try expectEqual(state(String(repeating: "a", count: 61), "Europe/Paris"),
                        .invalidName, "over the length bound")
        // Unknown IANA identifier.
        try expectEqual(state("Office", "Not/AZone"), .unknownZone, "unknown id")
        try expectEqual(state("Office", "Europe/Paris"), .active, "valid row")
        // The whole-row pass preserves order.
        let zones = [
            CustomTimeZone(name: "Office", identifier: "Europe/Paris"),
            CustomTimeZone(name: "", identifier: ""),
            CustomTimeZone(name: "NotaZone", identifier: "Nope/Nope"),
        ]
        let states = CustomTimeZoneEditor.states(zones, catalog: catalog)
        try expectEqual(states, [.active, .empty, .unknownZone], "per-row states")
        // Only active rows reach the lane.
        try expectEqual(CustomTimeZoneEditor.activeZones(zones, catalog: catalog).count, 1,
                        "one active row")
    },

    EngineCase("timezone-settings-name-collisions") {
        let catalog = TimezoneCatalog.shared
        // Case- and whitespace-insensitive duplicate detection.
        let existing = [CustomTimeZone(name: "My Office", identifier: "Europe/Paris")]
        try expectEqual(CustomTimeZoneEditor.state(name: "  my   OFFICE ", identifier: "Asia/Tokyo",
                                                   zones: existing, catalog: catalog),
                        .duplicate, "case/whitespace-insensitive duplicate")
        try expectEqual(CustomTimeZoneEditor.state(name: "My Office", identifier: "Asia/Tokyo",
                                                   zones: existing, excluding: existing[0].id,
                                                   catalog: catalog),
                        .active, "the row never duplicates itself")
        // Built-in sources are reserved: city, country name, country code,
        // airport code, fixed abbreviation and GMT syntax.
        for reserved in ["Paris", "Japan", "JP", "LAX", "PST", "GMT", "GMT+5", "UTC"] {
            try expectEqual(CustomTimeZoneEditor.isBuiltInName(reserved, catalog: catalog), true,
                            "\(reserved) is bundled")
            try expectEqual(CustomTimeZoneEditor.state(name: reserved,
                                                       identifier: "Asia/Tokyo",
                                                       catalog: catalog),
                            .builtInCollision, "\(reserved) is reserved")
        }
        // An IANA id is bundled too; as an alias its slash already fails
        // the name shape, so it can never become active either way.
        try expectEqual(CustomTimeZoneEditor.isBuiltInName("Europe/Paris", catalog: catalog),
                        true, "an IANA id is bundled")
        try expect(CustomTimeZoneEditor.state(name: "Europe/Paris", identifier: "Asia/Tokyo",
                                              catalog: catalog) != .active,
                   "an IANA-id alias never activates")
        // A genuinely fresh name passes.
        try expectEqual(CustomTimeZoneEditor.isBuiltInName("HQ", catalog: catalog), false,
                        "HQ is fresh")
        try expectEqual(CustomTimeZoneEditor.state(name: "HQ", identifier: "Asia/Tokyo",
                                                   catalog: catalog),
                        .active, "HQ is active")
        // Generated names avoid custom AND built-in collisions.
        let taken = Set(["Alias", "alias 2"].map(CustomTimeZoneEditor.canonicalName))
        let generated = CustomTimeZoneEditor.generatedName(taken: taken, catalog: catalog)
        try expectEqual(CustomTimeZoneEditor.canonicalName(generated), "alias 3",
                        "the next free generated name")
    },

    EngineCase("timezone-settings-cap") {
        // The constructor and the editor share the 100-row cap.
        let many = (0..<120).map { CustomTimeZone(name: "Zone \($0)", identifier: "Europe/Paris") }
        let prefs = TemporalPreferences(customTimeZones: many)
        try expectEqual(prefs.customTimeZones.count, TemporalPreferences.maxCustomTimeZones,
                        "constructed zones are capped")
        // Duplicate rows all report the duplicate state (nothing is dropped).
        let zones = [CustomTimeZone(name: "Office", identifier: "Europe/Paris"),
                     CustomTimeZone(name: " office ", identifier: "Asia/Tokyo")]
        let states = CustomTimeZoneEditor.states(zones)
        try expectEqual(states, [.duplicate, .duplicate], "both rows report the duplicate")
        try expectEqual(CustomTimeZoneEditor.activeZones(zones).count, 0, "none active")
    },

    EngineCase("timezone-settings-live-lane-consumption") {
        // The ACTIVE row is consumed live by the existing TimezoneLane.
        var prefs = TemporalPreferences.defaults
        prefs.customTimeZones = [CustomTimeZone(name: "HQ", identifier: "Asia/Tokyo")]
        try expectEqual(tzSettingsText("time in HQ", preferences: prefs), "7:00 pm",
                        "custom alias answers in the lane")
        // Case/whitespace-insensitive alias lookup.
        try expectEqual(tzSettingsText("time in   hq ", preferences: prefs), "7:00 pm",
                        "alias lookup is normalized")
        // An INACTIVE (unknown-id) row is ignored; the line fails closed.
        var broken = prefs
        broken.customTimeZones = [CustomTimeZone(name: "HQ", identifier: "Not/AZone")]
        guard case .error? = tzSettingsEval("time in HQ", preferences: broken) else {
            throw CaseFailure(message: "an inactive row must not answer", location: "TimezoneSettings")
        }
        // A stale row whose name steals a bundled place never shadows it.
        var thief = TemporalPreferences.defaults
        thief.customTimeZones = [CustomTimeZone(name: "Paris", identifier: "Asia/Tokyo")]
        try expectEqual(tzSettingsText("time in Paris", preferences: thief), "12:00 pm",
                        "a bundled city is never stolen by a custom alias")
        // Without preferences the alias is unknown (the app-global-only rule).
        try expectEqual(tzSettingsText("time in HQ", preferences: .defaults), nil,
                        "no preferences, no answer")
    },

    EngineCase("timezone-settings-localization-completeness") {
        for lang in AppLanguage.allCases {
            for key in tzSettingsKeys {
                let text = L10n.t(key, language: lang)
                try expect(text != key, "\(lang.rawValue): \(key) is translated")
                try expect(!text.trimmingCharacters(in: .whitespaces).isEmpty,
                           "\(lang.rawValue): \(key) is non-empty")
            }
        }
        // The visible tile label is concise and the page title is full.
        try expectEqual(L10n.t("settings.datesTimes", language: .en), "Dates & Times",
                        "English full title")
        try expectEqual(L10n.t("settings.datesTimesShort", language: .en), "Dates",
                        "English short title")
        try expectEqual(L10n.t("settings.datesTimes", language: .ru), "Дата и время",
                        "Russian full title")
        // The status vocabulary is distinct per language.
        for lang in AppLanguage.allCases {
            let active = L10n.t("timezones.status.active", language: lang)
            let unknown = L10n.t("timezones.status.unknownZone", language: lang)
            try expect(active != unknown, "\(lang.rawValue): distinct statuses")
        }
    },

    EngineCase("timezone-settings-destination-contract") {
        let text = tzSettingsSource("Sources/NumlexApp/Views/SettingsView.swift")
        // Exactly SEVEN destinations in the mandated order.
        let order = ["general", "editing", "numbers", "datesTimes",
                     "constantsUnits", "styling", "about"]
        var last = -1
        for name in order {
            guard let r = text.range(of: "case \(name)\n") else {
                throw CaseFailure(message: "missing destination case \(name)",
                                  location: "TimezoneSettings")
            }
            let idx = text.distance(from: text.startIndex, to: r.lowerBound)
            try expect(idx > last, "\(name) appears in navigation order")
            last = idx
        }
        try expect(text.contains("case .datesTimes: DatesTimesSettingsPage(model: model)"),
                   "Dates & Times has a detail branch")
        try expect(text.contains("case .datesTimes: return \"settings.datesTimesShort\""),
                   "a concise tile label exists")
        try expect(text.contains("case .datesTimes: return \"calendar\""),
                   "the tile uses the calendar SF Symbol")
        // Geometry source contract (content bounds unchanged).
        for pin in ["minWidth: CGFloat = 520", "idealWidth: CGFloat = 560",
                    "maxWidth: CGFloat = 640", "minHeight: CGFloat = 500",
                    "idealHeight: CGFloat = 540", "maxHeight: CGFloat = 640",
                    "navigationTileWidth: CGFloat = 66",
                    "navigationTileHeight: CGFloat = 50"] {
            try expect(text.contains(pin), "geometry keeps \(pin)")
        }
        // Seven tiles fit the minimum width: 7 * 66 + 6 * 2 spacing = 474 < 520.
        try expect(7 * 66 + 6 * 2 <= 520, "seven tiles fit the 520 pt minimum")
        // No fake chrome on the new page either.
        let code = text
        try expect(!code.contains("NSTitlebarAccessoryViewController"), "no fake titlebar")
        try expect(!code.contains("NSVisualEffectView"), "no fake material")
    },

    EngineCase("timezone-settings-persistence-and-nlx-isolation") {
        var settings = AppSettings()
        settings.temporal.customTimeZones = [
            CustomTimeZone(name: "Office", identifier: "Europe/Paris"),
            CustomTimeZone(name: "HQ", identifier: "Asia/Tokyo"),
        ]
        settings.temporal.hoursPerWorkday = 7.5
        let data = try JSONEncoder().encode(settings)
        let back = try JSONDecoder().decode(AppSettings.self, from: data)
        try expectEqual(back.temporal.customTimeZones.count, 2, "zones roundtrip")
        try expectEqual(back.temporal.customTimeZones[1].name, "HQ", "names roundtrip")
        try expectEqual(back.temporal.customTimeZones[0].id,
                        settings.temporal.customTimeZones[0].id, "stable UUIDs roundtrip")
        try expectEqual(back.temporal.hoursPerWorkday, 7.5, "work hours roundtrip")
        // A legacy store without the temporal block keeps its defaults and
        // every other setting; a malformed block cannot lose the store.
        let legacy = Data(#"{"decimalPlaces": 10, "fontSizeKey": "tf", "language": "en", "sheetName": "Sheet", "lineNumbers": true, "hideSidebarButtonWhenCollapsed": false, "showTotalBar": true, "fontColor": "white"}"#.utf8)
        let legacySettings = try JSONDecoder().decode(AppSettings.self, from: legacy)
        try expectEqual(legacySettings.temporal, TemporalPreferences.defaults,
                        "legacy store defaults")
        let malformed = Data(#"{"decimalPlaces": 10, "fontSizeKey": "tf", "language": "en", "sheetName": "Sheet", "lineNumbers": true, "hideSidebarButtonWhenCollapsed": false, "showTotalBar": true, "fontColor": "white", "temporal": 42}"#.utf8)
        let recovered = try JSONDecoder().decode(AppSettings.self, from: malformed)
        try expectEqual(recovered.temporal, TemporalPreferences.defaults,
                        "malformed temporal block ignored")
        // `.nlx` NEVER carries temporal settings.
        let export = SheetExport(title: "Sheet", content: "1+1")
        let json = String(data: try JSONEncoder().encode(export), encoding: .utf8) ?? ""
        for banned in ["temporal", "timezone", "timeZone", "customTimeZone",
                       "hoursPerWorkday", "holidayRegion"] {
            try expect(!json.contains(banned), "export has no \(banned)")
        }
        // Old `.nlx` files decode.
        let old = Data(#"{"title": "Sheet", "content": "1+1"}"#.utf8)
        let oldExport = try JSONDecoder().decode(SheetExport.self, from: old)
        try expectEqual(oldExport.content, "1+1", "legacy export decodes")
    },

    EngineCase("timezone-settings-editor-state-preservation") {
        let model = tzSettingsSource("Sources/NumlexApp/AppModel.swift")
        // The mutation family only touches settings.temporal.customTimeZones
        // and persists once per call: sheets/content/line IDs/references and
        // selection are never named inside the three methods.
        guard let start = model.range(of: "// MARK: Custom timezones")?.lowerBound,
              let end = model.range(of: "func exportCurrent()")?.lowerBound else {
            throw CaseFailure(message: "mutation section not found", location: "TimezoneSettings")
        }
        let section = String(model[start..<end])
        // Compare CODE, not the surrounding documentation comments.
        let code = section.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let t = line.trimmingCharacters(in: .whitespaces)
                return (t.hasPrefix("///") || t.hasPrefix("//")) ? "" : String(line)
            }
            .joined(separator: "\n")
        for touched in ["sheets", "selectedIndex", "lineIDs", "references", "content"] {
            // `TemporalPreferences` contains the substring `references`.
            let haystack = code.replacingOccurrences(of: "TemporalPreferences", with: "")
            try expect(!haystack.contains(touched),
                       "the mutation API never touches \(touched)")
        }
        try expectEqual(code.components(separatedBy: "persist()").count - 1, 3,
                        "each mutation persists exactly once")
        try expect(section.contains("settings.temporal.customTimeZones.insert") ||
                    section.contains("settings.temporal.customTimeZones.append"),
                    "add appends/inserts")
        try expect(section.contains("settings.temporal.customTimeZones.removeAll"),
                    "delete removes")
        // The view routes every edit through the ONE mutation API.
        let view = tzSettingsSource("Sources/NumlexApp/Views/SettingsView.swift")
        guard let pageStart = view.range(of: "private struct DatesTimesSettingsPage")?.lowerBound,
              let pageEnd = view.range(of: "// MARK: - Numbers tab")?.lowerBound else {
            throw CaseFailure(message: "DatesTimes page not found", location: "TimezoneSettings")
        }
        let page = String(view[pageStart..<pageEnd])
        try expect(page.contains("model.addCustomTimeZone()"), "the Add button uses the API")
        try expect(page.contains("model.addCustomTimeZone(after: zone.id)"),
                   "Enter inserts after the row")
        try expect(page.contains("model.updateCustomTimeZone(id: zone.id"), "edits use the API")
        try expect(page.contains("model.deleteCustomTimeZone(id: zone.id)"),
                   "delete uses the API")
        // Focus + VoiceOver.
        try expect(page.contains("@FocusState private var focusedZone"), "row focus state")
        try expect(page.contains(".focused($focusedZone, equals: zone.id)"), "focus handoff")
        try expect(page.contains(".accessibilityLabel"), "VoiceOver labels")
        // Not a sheet-metadata field anywhere in the export model.
        let sheet = tzSettingsSource("Sources/NumlexCore/Models/Sheet.swift")
        guard let exportStart = sheet.range(of: "public struct SheetExport")?.lowerBound,
              let exportEnd = sheet.range(of: "}\n", range: exportStart..<sheet.endIndex)?.upperBound else {
            throw CaseFailure(message: "SheetExport not found", location: "TimezoneSettings")
        }
        let exportStruct = String(sheet[exportStart..<exportEnd])
        try expect(!exportStruct.contains("Temporal"), "SheetExport has no temporal field")
        try expect(!exportStruct.contains("TimeZone"), "SheetExport has no timezone field")
    },
]
