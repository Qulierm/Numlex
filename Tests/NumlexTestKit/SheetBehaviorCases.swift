import Foundation
import NumlexCore

/// Sheet Behavior (General Settings) contracts: additive persistence,
/// the one-time launch decision, the fresh-sheet template, the
/// presentation-only sidebar order and the ⌘N routing.
private func sheetBehaviorSource(_ relativePath: String) -> String? {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // NumlexTestKit
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repository root
    let url = root.appendingPathComponent(relativePath).standardizedFileURL
    return try? String(contentsOf: url, encoding: .utf8)
}

private func sheetBehaviorCount(_ needle: String, in haystack: String) -> Int {
    guard !needle.isEmpty else { return 0 }
    var count = 0
    var rest = haystack
    while let r = rest.range(of: needle) {
        count += 1
        rest = String(rest[r.upperBound...])
    }
    return count
}

/// The 19 Sheet Behavior keys that must exist in every language table.
private let sheetBehaviorKeys = [
    "general.sheetBehavior", "launchBehavior", "launchBehaviorCap",
    "launchBehavior.lastEdited", "launchBehavior.newSheet",
    "commandN", "commandNCap", "commandN.newSheet", "commandN.newWindow",
    "newSheetStart", "newSheetStartCap", "newSheetStart.regularLine",
    "newSheetStart.heading", "sidebarSort", "sidebarSortCap",
    "sidebarSort.dateEdited", "sidebarSort.dateCreated", "sidebarSort.name",
    "newWindow"
]

public let sheetBehaviorCases: [EngineCase] = [
    EngineCase("sheet-behavior-legacy-store-decodes-defaults") {
        // Every earlier store has none of the four keys: each falls back
        // to the documented default WITHOUT failing the store, and the
        // payload version stays 2 (nothing is migrated).
        let json = """
        {"sheets":[],"selectedIndex":0,
         "settings":{"decimalPlaces":7,"fontSizeKey":"ts","language":"ru",
                     "sheetName":"S","lineNumbers":false,"fontColor":"white"},
         "version":2}
        """
        let payload = try JSONDecoder().decode(StorePayload.self, from: Data(json.utf8))
        try expectEqual(payload.version, 2, "store version unchanged")
        try expectEqual(payload.settings.launchBehavior, .lastEdited)
        try expectEqual(payload.settings.commandN, .newSheet)
        try expectEqual(payload.settings.newSheetStart, .regularLine)
        try expectEqual(payload.settings.sidebarSort, .dateEdited)
    },
    EngineCase("sheet-behavior-malformed-values-fall-back-independently") {
        // Unknown raw values AND wrong JSON types must each fall back on
        // their own: a corrupt `commandN` never disturbs a valid
        // `sidebarSort`.
        let json = """
        {"sheets":[],"selectedIndex":0,
         "settings":{"decimalPlaces":7,"fontSizeKey":"ts","language":"en",
                     "sheetName":"S","lineNumbers":false,"fontColor":"white",
                     "launchBehavior":"sometimes","commandN":17,
                     "newSheetStart":true,"sidebarSort":"name"},
         "version":2}
        """
        let payload = try JSONDecoder().decode(StorePayload.self, from: Data(json.utf8))
        try expectEqual(payload.settings.launchBehavior, .lastEdited, "unknown raw falls back")
        try expectEqual(payload.settings.commandN, .newSheet, "wrong type falls back")
        try expectEqual(payload.settings.newSheetStart, .regularLine, "wrong type falls back")
        try expectEqual(payload.settings.sidebarSort, .name, "a valid sibling value survives")
        // Every resolve() also handles a fully missing value.
        try expectEqual(LaunchSheetBehavior.resolve(nil), .lastEdited)
        try expectEqual(CommandNBehavior.resolve(nil), .newSheet)
        try expectEqual(NewSheetStart.resolve(nil), .regularLine)
        try expectEqual(SidebarSortOrder.resolve(nil), .dateEdited)
    },
    EngineCase("sheet-behavior-round-trips-through-the-store") {
        var settings = AppSettings.defaults
        settings.launchBehavior = .newSheet
        settings.commandN = .newWindow
        settings.newSheetStart = .heading
        settings.sidebarSort = .dateCreated
        let payload = StorePayload(sheets: [Sheet(title: "A", content: "1 + 1")],
                                   selectedIndex: 0, settings: settings,
                                   version: 2, folders: [])
        let data = try JSONEncoder().encode(payload)
        let back = try JSONDecoder().decode(StorePayload.self, from: data)
        try expectEqual(back.version, 2)
        try expectEqual(back.settings.launchBehavior, .newSheet)
        try expectEqual(back.settings.commandN, .newWindow)
        try expectEqual(back.settings.newSheetStart, .heading)
        try expectEqual(back.settings.sidebarSort, .dateCreated)
    },
    EngineCase("sheet-behavior-launch-last-edited-selection") {
        let t0 = Date(timeIntervalSince1970: 100)
        let t1 = Date(timeIntervalSince1970: 200)
        let t2 = Date(timeIntervalSince1970: 300)
        let sheets = [
            Sheet(title: "a", content: "", createdAt: t0, modifiedAt: t1),
            Sheet(title: "b", content: "", createdAt: t0, modifiedAt: t2),
            Sheet(title: "c", content: "", createdAt: t0, modifiedAt: t0)
        ]
        try expectEqual(SheetLaunch.initialSelection(behavior: .lastEdited,
                                                     sheets: sheets, persistedIndex: 0), 1,
                        "the newest edit wins")
        // An exact tie RETAINS the persisted selection when it is tied.
        let tied = [
            Sheet(title: "a", content: "", createdAt: t0, modifiedAt: t2),
            Sheet(title: "b", content: "", createdAt: t0, modifiedAt: t2),
            Sheet(title: "c", content: "", createdAt: t0, modifiedAt: t0)
        ]
        try expectEqual(SheetLaunch.initialSelection(behavior: .lastEdited,
                                                     sheets: tied, persistedIndex: 1), 1,
                        "a tied persisted selection survives")
        // …and otherwise the FIRST tied sheet in global order wins.
        try expectEqual(SheetLaunch.initialSelection(behavior: .lastEdited,
                                                     sheets: tied, persistedIndex: 2), 0,
                        "an untied selection falls back to stable global order")
        // `.newSheet` keeps the restored (clamped) selection; the caller
        // then creates the launch sheet in that sheet's folder.
        try expectEqual(SheetLaunch.initialSelection(behavior: .newSheet,
                                                     sheets: sheets, persistedIndex: 9), 2,
                        "clamped to the last sheet")
        try expectEqual(SheetLaunch.initialSelection(behavior: .lastEdited,
                                                     sheets: [], persistedIndex: 4), 0,
                        "an empty store resolves to 0")
    },
    EngineCase("sheet-behavior-fresh-sheet-template-and-caret") {
        try expectEqual(NewSheetTemplate.content(for: .regularLine), "")
        try expectEqual(NewSheetTemplate.caretOffset(for: .regularLine), 0)
        try expectEqual(NewSheetTemplate.content(for: .heading), "# ")
        try expectEqual(NewSheetTemplate.caretOffset(for: .heading), 2)
        // A heading sheet carries exactly one logical line and therefore
        // exactly one stable line ID.
        let heading = Sheet(title: "Sheet 1", content: NewSheetTemplate.content(for: .heading))
        try expectEqual(heading.logicalLineCount, 1)
        try expectEqual(heading.lineIDs.count, 1)
        try expectEqual((heading.content as NSString).length, 2,
                        "the caret offset addresses past '# '")
        let regular = Sheet(title: "Sheet 1", content: NewSheetTemplate.content(for: .regularLine))
        try expectEqual(regular.lineCount, 0)
        try expectEqual(regular.logicalLineCount, 1)
        try expectEqual(regular.lineIDs.count, 1)
    },
    EngineCase("sheet-behavior-sidebar-sorting-is-presentation-only") {
        let t0 = Date(timeIntervalSince1970: 10)
        let t1 = Date(timeIntervalSince1970: 20)
        let entries: [(index: Int, sheet: Sheet)] = [
            (0, Sheet(title: "Beta", content: "", createdAt: t1, modifiedAt: t0)),
            (1, Sheet(title: "alpha", content: "", createdAt: t0, modifiedAt: t1)),
            (2, Sheet(title: "Gamma", content: "", createdAt: t0, modifiedAt: t1))
        ]
        try expectEqual(SheetSorting.sorted(entries, by: .dateEdited).map(\.index), [1, 2, 0],
                        "newest edit first, ties in global order")
        try expectEqual(SheetSorting.sorted(entries, by: .dateCreated).map(\.index), [0, 1, 2],
                        "newest creation first")
        try expectEqual(SheetSorting.sorted(entries, by: .name).map(\.index), [1, 0, 2],
                        "localized-standard ascending name")
        // The helper only REORDERS the pairs: the same global indices and
        // the same sheets come back, so the caller's array is untouched.
        for order in SidebarSortOrder.uiOrder {
            let out = SheetSorting.sorted(entries, by: order)
            try expectEqual(out.map(\.index).sorted(), [0, 1, 2], "same global indices")
            try expectEqual(out.map(\.sheet.id).sorted(by: { $0.uuidString < $1.uuidString }),
                            entries.map(\.sheet.id).sorted(by: { $0.uuidString < $1.uuidString }),
                            "same sheets")
        }
        try expectEqual(SheetSorting.sorted([], by: .name).count, 0)
    },
    EngineCase("sheet-behavior-source-contracts") {
        guard let model = sheetBehaviorSource("Sources/NumlexApp/AppModel.swift"),
              let app = sheetBehaviorSource("Sources/NumlexApp/NumlexApp.swift"),
              let settingsView = sheetBehaviorSource("Sources/NumlexApp/Views/SettingsView.swift")
        else {
            throw CaseFailure(message: "Sheet Behavior sources missing")
        }
        // The launch preference is applied exactly ONCE, from init().
        try expectEqual(sheetBehaviorCount("\n        applyLaunchBehavior()", in: model), 1,
                        "one call site for the launch decision")
        try expect(model.contains("private func applyLaunchBehavior()"),
                   "the launch decision is one private method")
        try expect(model.contains("SheetLaunch.initialSelection("),
                   "last-edited selection goes through the pure helper")
        // Fresh sheets: one construction path for every creation site.
        try expect(model.contains("private func freshSheet(in folder: UUID?, ordinal: Int) -> Sheet"),
                   "one fresh-sheet constructor")
        try expect(model.contains("content: NewSheetTemplate.content(for: settings.newSheetStart)"),
                   "the configured template is the content source")
        try expect(model.contains("focusCaret = NewSheetTemplate.caretOffset(for: settings.newSheetStart)"),
                   "the template's caret offset is armed")
        try expect(model.contains("let idx = insertFreshSheet(in: dest)"),
                   "toolbar/menu/folder creation uses the shared path")
        try expect(model.contains("let replacement = freshSheet(in: folder, ordinal: 1)"),
                   "sole-sheet replacement uses the shared path")
        // Sorting is presentation-only.
        try expect(model.contains("return SheetSorting.sorted(entries, by: settings.sidebarSort)"),
                   "the sidebar list is sorted through the pure helper")
        try expect(!model.contains("sheets.sort"),
                   "the persisted array is never reordered")
        // A rename is an edit.
        try expect(model.contains("sheets[idx].modifiedAt = Date()"),
                   "renaming updates modifiedAt")
        // ⌘N routing lives in ONE commands type and routes at invocation.
        try expect(app.contains("WindowGroup(id: Self.mainWindowID)"),
                   "the main window group has a stable id")
        try expect(app.contains("static let mainWindowID"),
                   "the scene id is declared once")
        try expect(app.contains("private struct NewItemCommand: View"),
                   "the New Item command is its own type (it needs openWindow)")
        try expect(app.contains("NewItemCommand(model: model)"),
                   "the File menu uses that one command")
        try expect(app.contains("switch model.settings.commandN"),
                   "the command reads the Sheet Behavior preference")
        try expect(app.contains("openWindow(id: NumlexApp.mainWindowID)"),
                   "New Window opens another main window")
        try expectEqual(sheetBehaviorCount("keyboardShortcut(\"n\", modifiers: .command)", in: app), 1,
                        "exactly one ⌘N owner")
        // General Settings owns the four pickers through the model setters.
        for setter in ["model.setLaunchBehavior($0)", "model.setCommandN($0)",
                       "model.setNewSheetStart($0)", "model.setSidebarSort($0)"] {
            try expect(settingsView.contains(setter), "General Settings wires \(setter)")
        }
        try expect(settingsView.contains("L10n.t(\"general.sheetBehavior\", language: language)"),
                   "the group is localized")
    },
    EngineCase("sheet-behavior-localization-parity") {
        for language in AppLanguage.allCases {
            guard let table = L10n.translations[language] else {
                throw CaseFailure(message: "missing table for \(language)")
            }
            for key in sheetBehaviorKeys {
                guard let value = table[key], !value.isEmpty else {
                    throw CaseFailure(message: "\(language) is missing \(key)")
                }
            }
        }
        // Exact spot checks so a table can never drift silently.
        try expectEqual(L10n.t("general.sheetBehavior", language: .en), "Sheet Behavior")
        try expectEqual(L10n.t("general.sheetBehavior", language: .ru), "Поведение листов")
        try expectEqual(L10n.t("launchBehavior.lastEdited", language: .ru),
                        "Открыть последний изменённый лист")
        try expectEqual(L10n.t("commandN.newWindow", language: .de), "Neues Fenster")
        try expectEqual(L10n.t("newSheetStart.heading", language: .zh), "标题")
        try expectEqual(L10n.t("sidebarSort.dateEdited", language: .fr), "Date de modification")
        try expectEqual(L10n.t("newWindow", language: .it), "Nuova finestra")
    }
]
