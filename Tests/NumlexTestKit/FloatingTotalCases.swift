import Foundation
import NumlexCore

/// Floating Total contracts: the contribution policy (which rows enter the
/// Sum/Average/Count/Median set), its persistence, and the layout/wiring
/// source contracts shared by the live footer and the export snapshot.
private func floatingTotalSource(_ relativePath: String) -> String? {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // NumlexTestKit
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repository root
    let url = root.appendingPathComponent(relativePath).standardizedFileURL
    return try? String(contentsOf: url, encoding: .utf8)
}

private let floatingTotalKeys = [
    "general.floatingTotal", "footerAvoidOverlap", "footerAvoidOverlapCap",
    "footerIncludeReferenced", "footerIncludeReferencedCap",
    "footerIncludeVariables", "footerIncludeVariablesCap"
]

/// One evaluated row: a plain scalar line.
private func ftNumber(_ value: Double) -> SheetLine {
    SheetLine(sourceLineIndex: 0, result: .number(value: value, unit: nil, kind: .plain, fraction: nil),
              isTotal: false)
}

private func ftVariable(_ value: Double) -> SheetLine {
    SheetLine(sourceLineIndex: 0,
              result: .variable(name: "x", value: value, kind: .plain, fraction: nil),
              isTotal: false)
}

private func ftVariableInt(_ value: Int64) -> SheetLine {
    SheetLine(sourceLineIndex: 0, result: .variableInt(name: "n", value: value, radix: 10),
              isTotal: false)
}

private func ftBlank() -> SheetLine {
    SheetLine(sourceLineIndex: 0, result: .blank, isTotal: false)
}

private func ftTotalRow(_ value: Double) -> SheetLine {
    SheetLine(sourceLineIndex: 0,
              result: .number(value: value, unit: nil, kind: .plain, fraction: nil),
              isTotal: true)
}

public let floatingTotalCases: [EngineCase] = [
    EngineCase("floating-total-show-and-overlap-placement-truth-table") {
        // Complete truth table: Show=false has ABSOLUTE precedence, the
        // summary must exist, and only then does Avoid overlap choose a
        // reserved sibling or an overlay.
        for avoidOverlap in [false, true] {
            try expectEqual(FooterTotalPlacement.resolve(show: false, hasSummary: true,
                                                         avoidOverlap: avoidOverlap), .hidden,
                            "Show off always hides")
            try expectEqual(FooterTotalPlacement.resolve(show: false, hasSummary: false,
                                                         avoidOverlap: avoidOverlap), .hidden,
                            "Show off + no summary hides")
            try expectEqual(FooterTotalPlacement.resolve(show: true, hasSummary: false,
                                                         avoidOverlap: avoidOverlap), .hidden,
                            "no summary hides even when Show is on")
        }
        try expectEqual(FooterTotalPlacement.resolve(show: true, hasSummary: true,
                                                     avoidOverlap: true), .reserved,
                        "Show on + Avoid overlap on reserves space")
        try expectEqual(FooterTotalPlacement.resolve(show: true, hasSummary: true,
                                                     avoidOverlap: false), .overlay,
                        "Show on + Avoid overlap off overlays")
    },
    EngineCase("floating-total-show-toggle-restores-selected-placement") {
        // Simulate both overlap settings across Show ON → OFF → ON. The
        // bar disappears while OFF, then restores exactly the selected
        // reserved/overlay mode when turned back on.
        for avoidOverlap in [false, true] {
            let selected = FooterTotalPlacement.resolve(show: true, hasSummary: true,
                                                        avoidOverlap: avoidOverlap)
            try expectEqual(selected, avoidOverlap ? .reserved : .overlay)
            try expectEqual(FooterTotalPlacement.resolve(show: false, hasSummary: true,
                                                         avoidOverlap: avoidOverlap), .hidden)
            try expectEqual(FooterTotalPlacement.resolve(show: true, hasSummary: true,
                                                         avoidOverlap: avoidOverlap), selected)
        }
    },
    EngineCase("floating-total-defaults-and-tolerant-decode") {
        // Every earlier store has none of the three keys: each decodes to
        // the historical behavior without failing the store, and the
        // payload version stays 2.
        let json = """
        {"sheets":[],"selectedIndex":0,
         "settings":{"decimalPlaces":7,"fontSizeKey":"ts","language":"en",
                     "sheetName":"S","lineNumbers":false,"fontColor":"white"},
         "version":2}
        """
        let payload = try JSONDecoder().decode(StorePayload.self, from: Data(json.utf8))
        try expectEqual(payload.version, 2)
        try expectEqual(payload.settings.showTotalBar, true)
        try expectEqual(payload.settings.footerAvoidOverlap, true)
        try expectEqual(payload.settings.footerIncludeReferencedLines, true)
        try expectEqual(payload.settings.footerIncludeVariableLines, true)
        try expectEqual(payload.settings.footerContributionPolicy, .defaults)
        // Malformed values fall back INDEPENDENTLY: a corrupt
        // showTotalBar and footerAvoidOverlap never disturb valid siblings.
        let bad = """
        {"sheets":[],"selectedIndex":0,
         "settings":{"decimalPlaces":7,"fontSizeKey":"ts","language":"en",
                     "sheetName":"S","lineNumbers":false,"fontColor":"white",
                     "footerAvoidOverlap":"maybe","footerIncludeReferencedLines":false,
                     "footerIncludeVariableLines":false},
         "version":2}
        """
        let malformedShow = bad.replacingOccurrences(of: "\"footerAvoidOverlap\"", with: "\"showTotalBar\":\"maybe\", \"footerAvoidOverlap\"")
        let p2 = try JSONDecoder().decode(StorePayload.self, from: Data(bad.utf8))
        let p3 = try JSONDecoder().decode(StorePayload.self, from: Data(malformedShow.utf8))
        try expectEqual(p3.settings.showTotalBar, true, "wrong Show type falls back independently")
        try expectEqual(p3.settings.footerIncludeReferencedLines, false, "valid sibling survives malformed Show")
        try expectEqual(p2.settings.footerAvoidOverlap, true, "wrong type falls back to the default")
        try expectEqual(p2.settings.footerIncludeReferencedLines, false)
        try expectEqual(p2.settings.footerIncludeVariableLines, false)
        // And a full roundtrip keeps an explicit OFF/OFF choice.
        var settings = AppSettings.defaults
        settings.showTotalBar = false
        settings.footerAvoidOverlap = false
        settings.footerIncludeReferencedLines = false
        settings.footerIncludeVariableLines = false
        let roundtrip = try JSONDecoder().decode(
            StorePayload.self,
            from: JSONEncoder().encode(StorePayload(sheets: [], selectedIndex: 0,
                                                    settings: settings, version: 2)))
        try expectEqual(roundtrip.settings.showTotalBar, false, "explicit OFF survives StorePayload JSON roundtrip")
        try expectEqual(roundtrip.settings.footerAvoidOverlap, false)
        try expectEqual(roundtrip.settings.footerContributionPolicy,
                        FooterContributionPolicy(includeReferencedLines: false,
                                                 includeVariableDeclarations: false))
    },
    EngineCase("floating-total-default-policy-is-the-legacy-footer") {
        let lines = [ftNumber(2), ftVariable(3), ftVariableInt(4), ftBlank(),
                     ftTotalRow(99), ftNumber(1.5)]
        let ids = (0..<6).map { _ in UUID() }
        let referenced: Set<UUID> = [ids[0], ids[1], ids[2]]
        let legacy = SheetFooterStatistics.compute(lines, statistic: .sum)
        let policy = SheetFooterStatistics.compute(lines, lineIDs: ids,
                                                   referencedSourceLineIDs: referenced,
                                                   policy: .defaults, statistic: .sum)
        try expectEqual(legacy?.doubleValue, 10.5, "2 + 3 + 4 + 1.5 (inline total excluded)")
        try expectEqual(policy?.doubleValue, 10.5, "the default policy is byte-for-byte the old total")
        // The legacy contributions helper is unchanged for every caller.
        try expectEqual(SheetFooterStatistics.contributions(lines), [2, 3, 4, 1.5])
    },
    EngineCase("floating-total-filters-apply-to-every-statistic") {
        // Rows: 0 = referenced source (10), 1 = variable (2), 2 = variableInt
        // (4), 3 = ordinary (6), 4 = token consumer (8).
        let lines = [ftNumber(10), ftVariable(2), ftVariableInt(4), ftNumber(6), ftNumber(8)]
        let ids = (0..<5).map { _ in UUID() }
        let referenced: Set<UUID> = [ids[0]]

        let none = FooterContributionPolicy(includeReferencedLines: false,
                                            includeVariableDeclarations: false)
        let noRefs = FooterContributionPolicy(includeReferencedLines: false,
                                              includeVariableDeclarations: true)
        let noVars = FooterContributionPolicy(includeReferencedLines: true,
                                              includeVariableDeclarations: false)

        // Values: default [10,2,4,6,8]; noRefs [2,4,6,8]; noVars [10,6,8];
        // none [6,8].
        try expectEqual(SheetFooterStatistics.contributions(lines, lineIDs: ids,
                                                            referencedSourceLineIDs: referenced,
                                                            policy: .defaults),
                        [10, 2, 4, 6, 8])
        try expectEqual(SheetFooterStatistics.contributions(lines, lineIDs: ids,
                                                            referencedSourceLineIDs: referenced,
                                                            policy: noRefs),
                        [2, 4, 6, 8], "the token SOURCE row drops, the consumer row stays")
        try expectEqual(SheetFooterStatistics.contributions(lines, lineIDs: ids,
                                                            referencedSourceLineIDs: referenced,
                                                            policy: noVars),
                        [10, 6, 8], "both declaration kinds drop")
        try expectEqual(SheetFooterStatistics.contributions(lines, lineIDs: ids,
                                                            referencedSourceLineIDs: referenced,
                                                            policy: none),
                        [6, 8], "both filters together")

        // All four statistics consume exactly the filtered set.
        func stat(_ policy: FooterContributionPolicy,
                  _ statistic: FooterStatistic) -> SheetFooterStatistics.Value? {
            SheetFooterStatistics.compute(lines, lineIDs: ids,
                                          referencedSourceLineIDs: referenced,
                                          policy: policy, statistic: statistic)
        }
        try expectEqual(stat(.defaults, .sum)?.doubleValue, 30)
        try expectEqual(stat(.defaults, .average)?.doubleValue, 6)
        try expectEqual(stat(.defaults, .count)?.countValue, 5)
        try expectEqual(stat(.defaults, .median)?.doubleValue, 6)
        try expectEqual(stat(none, .sum)?.doubleValue, 14)
        try expectEqual(stat(none, .average)?.doubleValue, 7)
        try expectEqual(stat(none, .count)?.countValue, 2)
        try expectEqual(stat(none, .median)?.doubleValue, 7)
        try expectEqual(stat(noRefs, .count)?.countValue, 4)
        try expectEqual(stat(noVars, .count)?.countValue, 3)
        try expectEqual(stat(noVars, .sum)?.doubleValue, 24)
    },
    EngineCase("floating-total-nothing-eligible-shows-no-footer") {
        // Filtering every row away means "nothing to show" (nil), exactly
        // like a sheet without eligible rows.
        let lines = [ftVariable(2), ftVariableInt(4)]
        let ids = [UUID(), UUID()]
        let noVars = FooterContributionPolicy(includeReferencedLines: true,
                                              includeVariableDeclarations: false)
        try expectEqual(SheetFooterStatistics.compute(lines, lineIDs: ids,
                                                      referencedSourceLineIDs: [],
                                                      policy: noVars, statistic: .sum), nil)
        try expectEqual(SheetFooterStatistics.compute(lines, lineIDs: ids,
                                                      referencedSourceLineIDs: [],
                                                      policy: noVars, statistic: .count), nil)
        // A short/absent line-ID table can never crash or mis-filter: the
        // row simply has no identity to match.
        try expectEqual(SheetFooterStatistics.contributions(lines, lineIDs: [],
                                                            referencedSourceLineIDs: Set(ids),
                                                            policy: FooterContributionPolicy(
                                                                includeReferencedLines: false,
                                                                includeVariableDeclarations: true)),
                        [2, 4])
    },
    EngineCase("floating-total-variable-declaration-detection") {
        try expectEqual(SheetFooterStatistics.isVariableDeclaration(
            .variable(name: "x", value: 1, kind: .plain, fraction: nil)), true)
        try expectEqual(SheetFooterStatistics.isVariableDeclaration(
            .variableInt(name: "n", value: 1, radix: 10)), true)
        try expectEqual(SheetFooterStatistics.isVariableDeclaration(.number(value: 1, unit: nil,
                                                                            kind: .plain, fraction: nil)), false)
        try expectEqual(SheetFooterStatistics.isVariableDeclaration(.money(value: 1, code: "USD")), false)
        try expectEqual(SheetFooterStatistics.isVariableDeclaration(.blank), false)
    },
    EngineCase("floating-total-export-parity-full-range-and-projection") {
        // The export snapshot must reproduce the live footer for the same
        // frozen policy, and a projection applies the policy to the rows it
        // kept. Three rows: a referenced source (4), a variable (5) and an
        // ordinary row (6).
        var sheet = Sheet(title: "T", content: "base\nx = 5\n\(answerTokenMarker) + 1")
        sheet.lineIDs = [UUID(), UUID(), UUID()]
        sheet.references = [AnswerReference(sourceLineID: sheet.lineIDs[0],
                                            labelLine: 1, location: 5)]
        var settings = AppSettings.defaults
        settings.footerIncludeReferencedLines = false
        settings.footerIncludeVariableLines = false

        let policy = settings.footerContributionPolicy
        let evaluated: [SheetLine] = [
            SheetLine(sourceLineIndex: 0,
                      result: .number(value: 4, unit: nil, kind: .plain, fraction: nil),
                      isTotal: false),
            SheetLine(sourceLineIndex: 1,
                      result: .variable(name: "x", value: 5, kind: .plain, fraction: nil),
                      isTotal: false),
            SheetLine(sourceLineIndex: 2,
                      result: .number(value: 6, unit: nil, kind: .plain, fraction: nil),
                      isTotal: false)
        ]
        let referenced = Set(sheet.references.map(\.sourceLineID))
        let live = SheetFooterStatistics.compute(evaluated,
                                                 lineIDs: sheet.lineIDs,
                                                 referencedSourceLineIDs: referenced,
                                                 policy: policy,
                                                 statistic: settings.footerStatistic)
        try expectEqual(live?.doubleValue, 6, "only the ordinary row counts")

        // The FULL-range export context carries the same policy and the
        // same referenced set (built from the sheet's references).
        let context = ExportPresentationContext(
            sheetID: sheet.id, sheetTitle: sheet.title, content: sheet.content,
            lineIDs: sheet.lineIDs, references: sheet.references,
            answerDisplay: sheet.answerDisplay, highlights: sheet.highlights,
            rates: Rates(), decimalPlaces: 7, now: Date(), calendar: Calendar(identifier: .gregorian),
            constants: [], weather: .empty, geo: .empty,
            numberContext: .legacy, unitContext: .builtIns,
            preferences: .defaults, financial: .defaults,
            presentation: .defaults, language: .en,
            footerStatistic: settings.footerStatistic,
            footerPolicy: policy)
        try expectEqual(context.footerPolicy, policy, "the policy is frozen into the presentation")
        try expectEqual(context.referencedSourceLineIDs, referenced,
                        "the referenced source set comes from the sheet's references")

        // A RANGE projection keeps only its rows and applies the same
        // policy to them: with rows 0 and 1 filtered out by range, the
        // exported total is the ordinary row alone.
        let projected = SheetFooterStatistics.compute([evaluated[2]],
                                                      lineIDs: [sheet.lineIDs[2]],
                                                      referencedSourceLineIDs: context.referencedSourceLineIDs,
                                                      policy: context.footerPolicy,
                                                      statistic: context.footerStatistic)
        try expectEqual(projected?.doubleValue, 6)
        // …and the default policy on the same projection reproduces the
        // legacy value for that single row.
        let projectedLegacy = SheetFooterStatistics.compute([evaluated[2]],
                                                            statistic: .sum)
        try expectEqual(projectedLegacy?.doubleValue, 6)
    },
    EngineCase("floating-total-source-contracts") {
        guard let column = floatingTotalSource("Sources/NumlexApp/Views/AnswerColumnView.swift"),
              let content = floatingTotalSource("Sources/NumlexApp/Views/ContentView.swift"),
              let settingsView = floatingTotalSource("Sources/NumlexApp/Views/SettingsView.swift"),
              let builder = floatingTotalSource("Sources/NumlexCore/Export/ExportSnapshotBuilder.swift"),
              let types = floatingTotalSource("Sources/NumlexCore/Export/ExportTypes.swift")
        else {
            throw CaseFailure(message: "Floating Total sources missing")
        }
        // The live footer consumes the policy + identities.
        try expect(column.contains("referencedSourceLineIDs: referencedSourceLineIDs"),
                   "the live statistic passes the referenced set")
        try expect(column.contains("policy: footerPolicy"),
                   "the live statistic passes the frozen policy")
        try expect(column.contains("lineIDs: lineIDs"),
                   "the live statistic passes the stable line IDs")
        // Reserved space vs overlay: ONE footer implementation, no second
        // scroll view, no animation of the answers' hit surface.
        try expect(column.contains("private var footerPlacement: FooterTotalPlacement"),
                   "one placement authority drives both branches")
        try expect(column.contains("FooterTotalPlacement.resolve(show: showTotalBar,"),
                   "Show and overlap go through the pure truth table")
        try expect(column.contains("if footerPlacement == .reserved, let s = summary {\n                footerBar(s)"),
                   "the reserved-space branch keeps today's VStack sibling")
        try expect(column.contains(".overlay(alignment: .bottom) {\n            if footerPlacement == .overlay, let s = summary {\n                footerBar(s)"),
                   "only the explicit overlay placement renders in the overlay")
        try expect(column.contains("private var footerVisible: Bool { footerPlacement != .hidden }"),
                   "hidden clears footer geometry in either layout mode")
        try expect(column.contains("private func footerBar("),
                   "both layouts share one footer implementation")
        try expect(!column.contains("ScrollView {"),
                   "the answer column never gains a second scroll view")
        try expect(column.contains("onScroll: onWheelScroll"),
                   "wheel forwarding is unchanged")
        // ContentView passes the same frozen policy to the live column and
        // to the export presentation.
        try expect(settingsView.contains("boolBinding(\\AppSettings.showTotalBar)"),
                   "Settings binds Show to persisted AppSettings")
        try expect(content.contains("showTotalBar: settings.showTotalBar"),
                   "ContentView passes persisted Show to the answer column")
        try expect(content.contains("footerPolicy: settings.footerContributionPolicy"),
                   "ContentView passes the policy to the column")
        try expect(content.contains("footerStatistic: settings.footerStatistic,\n            footerPolicy: settings.footerContributionPolicy,"),
                   "the export presentation freezes statistic AND policy")
        try expect(content.contains(".map(\\.sourceLineID)"),
                   "ContentView derives the referenced source set from the sheet")
        // Export builder + context.
        try expect(types.contains("public let footerPolicy: FooterContributionPolicy"),
                   "the export context carries the policy")
        try expect(types.contains("self.referencedSourceLineIDs = Set(references.map(\\.sourceLineID))"),
                   "the export context freezes the referenced sources")
        try expect(builder.contains("lineIDs: rows.map(\\.lineID)"),
                   "the exported total uses the exported rows' stable IDs")
        try expect(builder.contains("policy: context.footerPolicy"),
                   "the exported total uses the frozen policy")
        // Settings: four switches in ONE group on the Notebook page, and
        // the Show control has a single owner.
        try expect(settingsView.contains("SettingsDetailPage(destination: .notebook, language: language)"),
                   "Floating Total belongs to Notebook")
        try expect(settingsView.contains("L10n.t(\"general.floatingTotal\", language: language)"),
                   "the Floating Total group is localized")
        try expectEqual(settingsView.components(separatedBy: "boolBinding(\\AppSettings.showTotalBar)").count - 1, 1,
                        "exactly one Show switch exists")
        for field in ["footerAvoidOverlap", "footerIncludeReferencedLines", "footerIncludeVariableLines"] {
            try expect(settingsView.contains("boolBinding(\\AppSettings.\(field))"),
                       "the \(field) switch is wired")
        }
        // Localization completeness and concise-caption regressions.
        let captionKeys = ["footerAvoidOverlapCap", "footerIncludeReferencedCap",
                           "footerIncludeVariablesCap"]
        // Swift String.count for each former caption, in captionKeys order.
        let formerCaptionLengths: [AppLanguage: [Int]] = [
            .en: [140, 137, 124], .ru: [124, 136, 148], .de: [144, 135, 143],
            .fr: [154, 140, 148], .it: [152, 147, 124], .zh: [37, 39, 48]
        ]
        for language in AppLanguage.allCases {
            guard let table = L10n.translations[language],
                  let formerLengths = formerCaptionLengths[language] else {
                throw CaseFailure(message: "missing localization table or caption baseline for \(language)")
            }
            for key in floatingTotalKeys {
                guard let value = table[key], !value.isEmpty else {
                    throw CaseFailure(message: "\(language) is missing \(key)")
                }
            }
            for (index, key) in captionKeys.enumerated() {
                guard let caption = table[key] else {
                    throw CaseFailure(message: "\(language) is missing \(key)")
                }
                try expect(caption.count <= 75, "\(language.rawValue) \(key) stays concise")
                try expect(caption.count * 4 <= formerLengths[index] * 3,
                           "\(language.rawValue) \(key) is at least 25% shorter than before")
            }
        }
        let overlapCaption = L10n.t("footerAvoidOverlapCap", language: .en).lowercased()
        let referencedCaption = L10n.t("footerIncludeReferencedCap", language: .en).lowercased()
        let variablesCaption = L10n.t("footerIncludeVariablesCap", language: .en).lowercased()
        try expect(overlapCaption.contains("off") && overlapCaption.contains("overlays"),
                   "English overlap caption explains OFF overlays answers")
        try expect(referencedCaption.contains("source") && referencedCaption.contains("answer token"),
                   "English referenced-lines caption identifies answer-token source rows")
        try expect(variablesCaption.contains("declaration") && variablesCaption.contains("x = 5"),
                   "English variables caption identifies declaration rows")
        try expectEqual(L10n.t("general.floatingTotal", language: .ru), "Плавающий итог")
        try expectEqual(L10n.t("footerAvoidOverlap", language: .de), "Antworten nicht überdecken")
        try expectEqual(L10n.t("footerIncludeReferenced", language: .zh), "包含被引用的行")
    }
]

extension SheetFooterStatistics.Value {
    /// Test-only convenience: the exact count of a `.count` statistic.
    var countValue: Int? {
        if case .count(let c) = self { return c }
        return nil
    }
}
