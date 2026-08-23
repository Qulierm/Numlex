import Foundation
import NumlexCore

/// Shared test cases for sheet naming, metric-to-answer placement and
/// backward-compatible store migration. Executed by both the Swift Testing
/// suite and the standalone `swift run NumlexTests` runner.
public let sheetCases: [EngineCase] = [
    // MARK: Automatic title extraction

    EngineCase("autotitle-from-expression") {
        let title = Sheet.autoTitle(from: "# notes\n12 + 30 * 2\n45.5 * 2", fallback: "Sheet 1")
        try expectEqual(title, "12 + 30 * 2", "first expression")
    },
    EngineCase("autotitle-from-assignment") {
        let title = Sheet.autoTitle(from: "price = 1250\nprice * 1.2", fallback: "Sheet 1")
        try expectEqual(title, "price = 1250", "assignment counts")
    },
    EngineCase("autotitle-from-conversion") {
        let title = Sheet.autoTitle(from: "10 km to meter", fallback: "Sheet 1")
        try expectEqual(title, "10 km to meter", "conversion counts")
    },
    EngineCase("autotitle-skips-comments-headings-notes") {
        let title = Sheet.autoTitle(from: "# c\n// Heading\nhello world\n\n7 + 1", fallback: "Sheet 1")
        try expectEqual(title, "7 + 1", "skips non-calculable lines")
    },
    EngineCase("autotitle-skips-error-lines") {
        let title = Sheet.autoTitle(from: "10 USD to RUB\n5 + 5", fallback: "Sheet 1")
        try expectEqual(title, "5 + 5", "rates-unavailable line is skipped")
    },
    EngineCase("autotitle-collapses-whitespace") {
        let title = Sheet.autoTitle(from: "  12   +   30  \n9", fallback: "Sheet 1")
        try expectEqual(title, "12 + 30", "whitespace collapsed")
    },
    EngineCase("autotitle-truncates-long-lines") {
        let long = String(repeating: "1 + ", count: 12) + "1"
        let title = Sheet.autoTitle(from: long + "\n9", fallback: "Sheet 1")
        try expect(title.count <= 28, "truncated to <= 28 chars")
        try expect(title.hasSuffix("…"), "ends with ellipsis")
    },
    EngineCase("autotitle-fallback-when-empty") {
        let title = Sheet.autoTitle(from: "  \n# only a note\n", fallback: "Sheet 3")
        try expectEqual(title, "Sheet 3", "falls back to seed")
    },

    // MARK: Custom title protection + auto update

    EngineCase("retitled-updates-automatic-title") {
        let sheet = Sheet(title: "Sheet 2", content: "", isTitleCustom: false)
        let updated = Sheet.retitled(sheet, content: "a = 10\na * 2")
        try expectEqual(updated.title, "a = 10", "title follows first calculation")
        try expectEqual(updated.isTitleCustom, false, "still automatic")
    },
    EngineCase("retitled-protects-custom-title") {
        let sheet = Sheet(title: "Самолет", content: "old", isTitleCustom: true)
        let updated = Sheet.retitled(sheet, content: "200 + 300")
        try expectEqual(updated.title, "Самолет", "custom title untouched")
        try expectEqual(updated.isTitleCustom, true, "still custom")
    },
    EngineCase("retitled-restores-seed-when-content-clears") {
        var sheet = Sheet(title: "Sheet 2", content: "5 + 5", isTitleCustom: false)
        sheet = Sheet.retitled(sheet, content: "5 + 5")
        try expectEqual(sheet.title, "5 + 5", "derived")
        sheet = Sheet.retitled(sheet, content: "")
        try expectEqual(sheet.title, "Sheet 2", "back to seed when cleared")
    },
    EngineCase("canonicalized-migrates-legacy-content") {
        // Regression: the init migration once called retitled(sheet,
        // content:) without assigning the canonical content, so persisted
        // legacy `*` survived. The helper must mutate the content itself.
        let legacy = Sheet(title: "12 * 3", content: "12*3\nx=5\nshopping list\n10 km to m",
                           isTitleCustom: false)
        let result = Sheet.canonicalized(legacy)
        try expect(result.changed, "legacy content reports changed")
        try expectEqual(result.sheet.content, "12 × 3\nx = 5\nshopping list\n10 km to m",
                        "math lines canonicalized, prose and conversion kept")
        try expectEqual(result.sheet.title, "12 × 3", "auto title follows canonical text")
        // Idempotence: an already-canonical sheet is left untouched, so
        // the app must not persist a store that needs no migration.
        let clean = Sheet(title: "7 + 1", content: "7 + 1\nkeep * as is",
                          isTitleCustom: false)
        try expectEqual(clean.content, NotebookFormatting.canonicalDocument(clean.content),
                        "precondition: already canonical")
        let cleanResult = Sheet.canonicalized(clean)
        try expect(!cleanResult.changed, "canonical sheet reports unchanged")
        try expectEqual(cleanResult.sheet, clean, "unchanged sheet is identical")
        // Custom titles survive migration while the content is still fixed.
        let custom = Sheet(title: "Самолет", content: "100*2", isTitleCustom: true)
        let customResult = Sheet.canonicalized(custom)
        try expect(customResult.changed, "content changed")
        try expectEqual(customResult.sheet.title, "Самолет", "custom title untouched")
        try expectEqual(customResult.sheet.content, "100 × 2", "content canonical")
    },
    EngineCase("generic-title-detection") {
        try expect(Sheet.isGenericTitle("Sheet"), "plain Sheet")
        try expect(Sheet.isGenericTitle("Sheet 2"), "Sheet N")
        try expect(Sheet.isGenericTitle("Лист 3"), "ru generic")
        try expect(!Sheet.isGenericTitle("Самолет"), "meaningful name is not generic")
        try expect(!Sheet.isGenericTitle("My Sheet"), "worded title is not generic")
    },

    // MARK: Backward-compatible store migration

    EngineCase("migration-legacy-custom-title") {
        let json = """
        {"id":"7AF433E2-2527-42A8-965F-7CED82612A3D","title":"Самолет","content":"236,287 + 87,459",
         "createdAt":809178642.8,"modifiedAt":809178642.8}
        """
        let sheet = try JSONDecoder().decode(Sheet.self, from: Data(json.utf8))
        try expectEqual(sheet.title, "Самолет", "title preserved")
        try expectEqual(sheet.isTitleCustom, true, "meaningful legacy name migrates to custom")
    },
    EngineCase("migration-legacy-generic-title") {
        let json = """
        {"id":"7AF433E2-2527-42A8-965F-7CED82612A3D","title":"Sheet 2","content":"5 + 5",
         "createdAt":809178642.8,"modifiedAt":809178642.8}
        """
        let sheet = try JSONDecoder().decode(Sheet.self, from: Data(json.utf8))
        try expectEqual(sheet.isTitleCustom, false, "generic legacy name stays automatic")
        try expectEqual(sheet.titleSeed, "Sheet 2", "seed carries the generic name")
    },
    EngineCase("migration-new-store-roundtrip") {
        let sheet = Sheet(title: "Flight", content: "100", isTitleCustom: true, titleSeed: "Sheet 9")
        let data = try JSONEncoder().encode(sheet)
        let decoded = try JSONDecoder().decode(Sheet.self, from: data)
        try expectEqual(decoded.isTitleCustom, true, "custom flag roundtrips")
        try expectEqual(decoded.titleSeed, "Sheet 9", "seed roundtrips")
    },
    EngineCase("export-import-custom-state") {
        let export = SheetExport(title: "My sheet", content: "1", isTitleCustom: true)
        let data = try JSONEncoder().encode(export)
        let decoded = try JSONDecoder().decode(SheetExport.self, from: data)
        try expectEqual(decoded.isTitleCustom, true, "export keeps custom state")
        // Legacy export without the key still decodes.
        let legacy = Data(#"{"title":"Old","content":"2"}"#.utf8)
        let old = try JSONDecoder().decode(SheetExport.self, from: legacy)
        try expectEqual(old.isTitleCustom, nil, "legacy export decodes with nil flag")
    },

    // MARK: Empty sheet display titles

    EngineCase("empty-automatic-sheet-displays-Empty") {
        let sheet = Sheet(title: "Sheet 2", content: "")
        try expectEqual(sheet.displayTitle(language: .en), "Empty", "new empty sheet shows Empty")
    },
    EngineCase("empty-custom-title-preserved") {
        let sheet = Sheet(title: "My Empty", content: "", isTitleCustom: true)
        try expectEqual(sheet.displayTitle(language: .en), "My Empty", "explicit rename stays, even when empty")
    },
    EngineCase("empty-after-content-cleared") {
        // Mirrors AppModel.updateContent: the caller assigns the new
        // content first, then applies the automatic-title rule.
        var sheet = Sheet(title: "Sheet 3", content: "5 + 5", isTitleCustom: false)
        sheet = Sheet.retitled(sheet, content: "5 + 5")
        try expectEqual(sheet.displayTitle(language: .en), "5 + 5", "derived title while content exists")
        sheet.content = ""
        sheet = Sheet.retitled(sheet, content: "")
        try expectEqual(sheet.title, "Sheet 3", "seed restored in the model")
        try expectEqual(sheet.displayTitle(language: .en), "Empty", "cleared automatic sheet shows Empty")
    },
    EngineCase("empty-legacy-generic-migration") {
        let json = """
        {"id":"7AF433E2-2527-42A8-965F-7CED82612A3D","title":"Sheet 4","content":"",
         "createdAt":809178642.8,"modifiedAt":809178642.8}
        """
        let sheet = try JSONDecoder().decode(Sheet.self, from: Data(json.utf8))
        try expectEqual(sheet.isTitleCustom, false, "legacy generic stays automatic")
        try expectEqual(sheet.displayTitle(language: .en), "Empty", "migrated empty sheet shows Empty")
    },
    EngineCase("empty-localized-titles") {
        let sheet = Sheet(title: "Sheet 1", content: "")
        try expectEqual(sheet.displayTitle(language: .ru), "Пусто", "ru Empty")
        try expectEqual(sheet.displayTitle(language: .de), "Leer", "de Empty")
        try expectEqual(sheet.displayTitle(language: .fr), "Vide", "fr Empty")
        try expectEqual(sheet.displayTitle(language: .it), "Vuoto", "it Empty")
        try expectEqual(sheet.displayTitle(language: .zh), "空", "zh Empty")
    },
    EngineCase("empty-no-lines-localization") {
        try expectEqual(L10n.t("noLines", language: .en), "No lines", "en No lines")
        try expectEqual(L10n.t("line", language: .en), "line", "en singular")
        try expectEqual(L10n.t("lines", language: .en), "lines", "en plural")
    },

    // MARK: Metrics-to-answer placement

    EngineCase("layout-single-line-rows") {
        let lines = [
            LineMetrics.Line(index: 0, top: 0, height: 30),
            LineMetrics.Line(index: 1, top: 30, height: 30),
        ]
        let row0 = NotebookLayout.answerRow(index: 0, lines: lines, topInset: 12)
        let row1 = NotebookLayout.answerRow(index: 1, lines: lines, topInset: 12)
        try expectEqual(row0.top, 12, "row0 top")
        try expectEqual(row0.height, 30, "row0 height")
        try expectEqual(row1.top, 42, "row1 top")
        try expectEqual(row1.height, 30, "row1 height")
    },
    EngineCase("layout-wrapped-block-heights") {
        // A logical line wrapped to three visual fragments keeps the full
        // block height, so its answer centers across all three lines.
        let lines = [
            LineMetrics.Line(index: 0, top: 0, height: 30),
            LineMetrics.Line(index: 1, top: 30, height: 90),
            LineMetrics.Line(index: 2, top: 120, height: 30),
        ]
        let row1 = NotebookLayout.answerRow(index: 1, lines: lines, topInset: 12)
        try expectEqual(row1.top, 42, "wrapped block top")
        try expectEqual(row1.height, 90, "wrapped block height")
    },
    EngineCase("layout-trailing-empty-line") {
        // "5 + 5\n" has a trailing empty logical line; the editor reports it.
        let lines = [
            LineMetrics.Line(index: 0, top: 0, height: 30),
            LineMetrics.Line(index: 1, top: 30, height: 30),
        ]
        let row1 = NotebookLayout.answerRow(index: 1, lines: lines, topInset: 12)
        try expectEqual(row1.top, 42, "trailing row top")
        try expectEqual(row1.height, 30, "trailing row height")
    },
    EngineCase("layout-row-containing-scroll-sync") {
        let lines = [
            LineMetrics.Line(index: 0, top: 0, height: 30),
            LineMetrics.Line(index: 1, top: 30, height: 90),
            LineMetrics.Line(index: 2, top: 120, height: 30),
        ]
        try expectEqual(NotebookLayout.rowContaining(offset: 0, lines: lines, topInset: 12, rowCount: 3), 0, "at top")
        try expectEqual(NotebookLayout.rowContaining(offset: 20, lines: lines, topInset: 12, rowCount: 3), 0, "inside row 0")
        try expectEqual(NotebookLayout.rowContaining(offset: 80, lines: lines, topInset: 12, rowCount: 3), 1, "middle of wrapped block")
        try expectEqual(NotebookLayout.rowContaining(offset: 500, lines: lines, topInset: 12, rowCount: 3), 2, "beyond content clamps to last")
    },
    EngineCase("layout-row-count-matches-sheet-rows") {
        // The metrics of a sheet must cover every evaluated row.
        let content = "12 + 30 * 2\n\n10 km to meter\nx = 4\n"
        var vars: [String: Double] = [:]
        let rows = evaluateSheet(content, variables: &vars, rates: Rates(), decimalPlaces: 7)
        // One line per logical source line, including the trailing empty one.
        let logical = content.components(separatedBy: "\n")
        try expectEqual(rows.count, logical.count, "rows cover every logical line")
    },
]
