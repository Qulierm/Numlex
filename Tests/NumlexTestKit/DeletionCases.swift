import Foundation
import NumlexCore

/// Pure selection planning for sheet deletion. The contract is checked
/// both by index AND by stable identity: after simulating the removal,
/// the sheet at `selectedIndexAfter` must be exactly the one the
/// contract says stays selected (the previous selection when an earlier
/// row was removed, the next sheet when the selected row was removed,
/// the previous one at the list end).
private func plan(_ count: Int, _ deleteIndex: Int, _ selectedIndex: Int) throws -> SheetDeletionPlan {
    guard let plan = sheetDeletionPlan(count: count,
                                       deleteIndex: deleteIndex,
                                       selectedIndex: selectedIndex) else {
        throw CaseFailure(message: "plan must exist for \(count)/\(deleteIndex)/\(selectedIndex)",
                          location: "DeletionCases")
    }
    return plan
}

private func selectedID(afterRemoving deleteIndex: Int,
                        in ids: [String],
                        plan: SheetDeletionPlan) -> String {
    var list = ids
    list.remove(at: plan.deleteIndex)
    return list[plan.selectedIndexAfter]
}

private func testUUID(_ value: Int) -> UUID {
    UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", value))")!
}

private func richSheet(_ id: Int,
                       title: String,
                       created: TimeInterval,
                       edited: TimeInterval,
                       folderID: UUID? = nil) -> Sheet {
    let firstLineID = testUUID(1_000 + id)
    let secondLineID = testUUID(2_000 + id)
    let content = "1 + 1\n\u{FFFC}"
    return Sheet(id: testUUID(id),
                 title: title,
                 content: content,
                 createdAt: Date(timeIntervalSince1970: created),
                 modifiedAt: Date(timeIntervalSince1970: edited),
                 isTitleCustom: true,
                 titleSeed: "seed-\(id)",
                 lineIDs: [firstLineID, secondLineID],
                 references: [AnswerReference(id: testUUID(3_000 + id),
                                              sourceLineID: firstLineID,
                                              labelLine: 1,
                                              location: 6)],
                 folderID: folderID,
                 answerDisplay: [AnswerDisplayPreference(lineID: firstLineID,
                                                         decimalPlaces: 4)],
                 highlights: [LineHighlightPreference(lineID: secondLineID,
                                                      color: .yellow)])
}

private func fullPlan(_ sheets: [Sheet],
                      _ deleteIndex: Int,
                      _ selectedIndex: Int,
                      _ sortOrder: SidebarSortOrder) throws -> SheetDeletionPlan {
    guard let result = sheetDeletionPlan(sheets: sheets,
                                         deleteIndex: deleteIndex,
                                         selectedIndex: selectedIndex,
                                         sortOrder: sortOrder) else {
        throw CaseFailure(message: "full-sheet plan must exist for \(sheets.count)/\(deleteIndex)/\(selectedIndex)/\(sortOrder)",
                          location: "DeletionCases")
    }
    return result
}

private func selectedSheetID(afterRemoving deleteIndex: Int,
                             from sheets: [Sheet],
                             plan: SheetDeletionPlan) -> UUID {
    var remaining = sheets
    remaining.remove(at: deleteIndex)
    return remaining[plan.selectedIndexAfter].id
}

private func deletionSource(_ relativePath: String) -> String? {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // NumlexTestKit
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repository root
    return try? String(contentsOf: root.appendingPathComponent(relativePath),
                       encoding: .utf8)
}

private func deletionSourceCount(_ needle: String, in haystack: String) -> Int {
    guard !needle.isEmpty else { return 0 }
    var count = 0
    var rest = haystack
    while let range = rest.range(of: needle) {
        count += 1
        rest = String(rest[range.upperBound...])
    }
    return count
}

private func deletionBody(in source: String) -> String? {
    guard let start = source.range(of: "    func deleteSheet(at index: Int) {"),
          let end = source.range(of: "\n    /// App-menu “Delete Sheet”",
                                range: start.lowerBound..<source.endIndex) else {
        return nil
    }
    return String(source[start.lowerBound..<end.lowerBound])
}

public let deletionCases: [EngineCase] = [
    EngineCase("deletion-earlier-row-deleted-keeps-same-sheet") {
        let ids = ["A", "B", "C", "D"]
        let p = try plan(4, 0, 1) // delete A while B is selected
        try expectEqual(p.replacesSoleSheet, false, "not the sole sheet")
        try expectEqual(p.selectedIndexAfter, 0, "index follows the down-shift")
        try expectEqual(selectedID(afterRemoving: 0, in: ids, plan: p), "B",
                        "the SAME selected sheet survives")
    },

    EngineCase("deletion-selected-row-picks-next") {
        let ids = ["A", "B", "C", "D"]
        let p = try plan(4, 1, 1) // delete B (selected, middle)
        try expectEqual(p.selectedIndexAfter, 1, "slot is taken by the next sheet")
        try expectEqual(selectedID(afterRemoving: 1, in: ids, plan: p), "C", "C becomes selected")
    },

    EngineCase("deletion-selected-last-row-picks-previous") {
        let ids = ["A", "B", "C", "D"]
        let p = try plan(4, 3, 3) // delete D, the selected last row
        try expectEqual(p.selectedIndexAfter, 2, "clamped to the previous row")
        try expectEqual(selectedID(afterRemoving: 3, in: ids, plan: p), "C", "C becomes selected")
    },

    EngineCase("deletion-later-row-deleted-keeps-same-sheet") {
        let ids = ["A", "B", "C", "D"]
        let p = try plan(4, 2, 0) // delete C while A is selected
        try expectEqual(p.selectedIndexAfter, 0, "selection index untouched")
        try expectEqual(selectedID(afterRemoving: 2, in: ids, plan: p), "A", "A stays selected")
    },

    EngineCase("deletion-two-sheet-lists") {
        let ids = ["A", "B"]
        let p1 = try plan(2, 0, 1) // delete A, B selected
        try expectEqual(p1.selectedIndexAfter, 0, "B slides to 0")
        try expectEqual(selectedID(afterRemoving: 0, in: ids, plan: p1), "B", "B stays selected")
        let p2 = try plan(2, 1, 1) // delete B, the selected last row
        try expectEqual(p2.selectedIndexAfter, 0, "previous row stays")
        try expectEqual(selectedID(afterRemoving: 1, in: ids, plan: p2), "A", "A stays selected")
    },

    EngineCase("deletion-sole-sheet-replaced") {
        let p = try plan(1, 0, 0)
        try expectEqual(p.replacesSoleSheet, true, "sole sheet is replaced, not removed")
        try expectEqual(p.selectedIndexAfter, 0, "selection stays at 0")
    },

    EngineCase("deletion-invalid-indices-rejected") {
        try expect(sheetDeletionPlan(count: 0, deleteIndex: 0, selectedIndex: 0) == nil,
                   "empty list has no plan")
        try expect(sheetDeletionPlan(count: 3, deleteIndex: 3, selectedIndex: 0) == nil,
                   "delete index out of range")
        try expect(sheetDeletionPlan(count: 3, deleteIndex: -1, selectedIndex: 0) == nil,
                   "negative delete index")
        try expect(sheetDeletionPlan(count: 3, deleteIndex: 0, selectedIndex: 3) == nil,
                   "selected index out of range")
    },

    EngineCase("deletion-active-default-selects-first-date-edited-survivor-by-identity") {
        let folder = testUUID(9_000)
        let sheets = [
            richSheet(1, title: "A", created: 10, edited: 20, folderID: folder),
            richSheet(2, title: "B", created: 20, edited: 10, folderID: folder),
            richSheet(3, title: "C", created: 30, edited: 30, folderID: folder),
        ]
        let before = sheets
        let legacy = try plan(sheets.count, 2, 2)
        try expectEqual(selectedID(afterRemoving: 2, in: ["A", "B", "C"], plan: legacy),
                        "B", "the legacy index-only overload retains its historical behavior")
        let corrected = try fullPlan(sheets, 2, 2, .dateEdited)
        try expectEqual(corrected.selectedIndexAfter, 0,
                        "A is before B after deleting C in the stored array")
        try expectEqual(selectedSheetID(afterRemoving: 2, from: sheets, plan: corrected),
                        sheets[0].id, "the actual latest-edited survivor A becomes active")
        try expectEqual(sheets, before,
                        "planning leaves rich survivor metadata, timestamps and global order untouched")
    },

    EngineCase("deletion-active-respects-date-created-and-name-sort-orders") {
        let createdSheets = [
            richSheet(10, title: "First", created: 10, edited: 100),
            richSheet(11, title: "Second", created: 30, edited: 5),
            richSheet(12, title: "Deleted", created: 20, edited: 70),
        ]
        let byCreated = try fullPlan(createdSheets, 2, 2, .dateCreated)
        try expectEqual(selectedSheetID(afterRemoving: 2, from: createdSheets, plan: byCreated),
                        createdSheets[1].id, "Date Created selects B despite A's newer edit")
        try expectEqual(byCreated.selectedIndexAfter, 1,
                        "a preferred survivor after the deleted global index shifts back once")

        let namedSheets = [
            richSheet(20, title: "Zulu", created: 30, edited: 20),
            richSheet(21, title: "Alpha", created: 10, edited: 100),
            richSheet(22, title: "Middle", created: 20, edited: 10),
        ]
        let byName = try fullPlan(namedSheets, 2, 2, .name)
        try expectEqual(selectedSheetID(afterRemoving: 2, from: namedSheets, plan: byName),
                        namedSheets[1].id, "Name selects the localized-standard first title")
        try expectEqual(byName.selectedIndexAfter, 1,
                        "the name-sorted survivor before deletion keeps its global slot")
    },

    EngineCase("deletion-active-sort-ties-use-existing-global-index-stability") {
        let folder = testUUID(9_001)
        let tied = [
            richSheet(30, title: "Same", created: 5, edited: 5, folderID: folder),
            richSheet(31, title: "Same", created: 5, edited: 5, folderID: folder),
            richSheet(32, title: "Same", created: 5, edited: 5, folderID: folder),
        ]
        for order in SidebarSortOrder.allCases {
            let result = try fullPlan(tied, 2, 2, order)
            try expectEqual(selectedSheetID(afterRemoving: 2, from: tied, plan: result),
                            tied[0].id,
                            "a complete sort tie falls back to the first existing global index for \(order)")
            try expectEqual(result.selectedIndexAfter, 0,
                            "the tied candidate before the deletion keeps its post-removal index")
        }
    },

    EngineCase("deletion-active-first-middle-last-and-repeated-selection") {
        let base = [
            richSheet(40, title: "A", created: 1, edited: 40),
            richSheet(41, title: "B", created: 2, edited: 30),
            richSheet(42, title: "C", created: 3, edited: 20),
            richSheet(43, title: "D", created: 4, edited: 10),
        ]
        for selected in [0, 1, 2, 3] {
            let result = try fullPlan(base, selected, selected, .dateEdited)
            var remaining = base
            remaining.remove(at: selected)
            let preferred = SheetSorting.sorted(remaining.enumerated().map { (index: $0.offset, sheet: $0.element) },
                                                by: .dateEdited)[0]
            try expectEqual(selectedSheetID(afterRemoving: selected, from: base, plan: result),
                            preferred.sheet.id,
                            "deleting an active first/middle/last row activates the first visible survivor")
        }

        var remaining = [
            richSheet(50, title: "A", created: 1, edited: 20),
            richSheet(51, title: "B", created: 2, edited: 10),
            richSheet(52, title: "C", created: 3, edited: 30),
        ]
        var activeIndex = 2
        for expectedID in [remaining[0].id, remaining[1].id] {
            let result = try fullPlan(remaining, activeIndex, activeIndex, .dateEdited)
            try expectEqual(selectedSheetID(afterRemoving: activeIndex, from: remaining, plan: result),
                            expectedID, "repeated active deletion follows each new sorted survivor")
            remaining.remove(at: activeIndex)
            activeIndex = result.selectedIndexAfter
        }
    },

    EngineCase("deletion-active-prefers-same-folder-before-newer-other-folder") {
        let targetFolder = testUUID(9_010)
        let otherFolder = testUUID(9_011)
        let sheets = [
            richSheet(60, title: "Target old", created: 1, edited: 10, folderID: targetFolder),
            richSheet(61, title: "Other newest", created: 2, edited: 100, folderID: otherFolder),
            richSheet(62, title: "Deleted target", created: 3, edited: 20, folderID: targetFolder),
        ]
        let result = try fullPlan(sheets, 2, 2, .dateEdited)
        try expectEqual(selectedSheetID(afterRemoving: 2, from: sheets, plan: result),
                        sheets[0].id,
                        "the deleted sheet's folder outranks a newer sheet in another folder")
    },

    EngineCase("deletion-active-empty-group-falls-back-to-global-sorted-survivor") {
        let deletedFolder = testUUID(9_020)
        let otherFolder = testUUID(9_021)
        let sheets = [
            richSheet(70, title: "Older", created: 1, edited: 10, folderID: otherFolder),
            richSheet(71, title: "Only deleted-group sheet", created: 2, edited: 5, folderID: deletedFolder),
            richSheet(72, title: "Globally newest", created: 3, edited: 30, folderID: otherFolder),
        ]
        let result = try fullPlan(sheets, 1, 1, .dateEdited)
        try expectEqual(result.selectedIndexAfter, 1,
                        "the globally sorted survivor after the deletion shifts back once")
        try expectEqual(selectedSheetID(afterRemoving: 1, from: sheets, plan: result),
                        sheets[2].id, "an empty deleted folder falls back to global Date Edited order")
    },

    EngineCase("deletion-active-general-nil-folder-and-global-fallback") {
        let otherFolder = testUUID(9_030)
        let generalSheets = [
            richSheet(80, title: "General older", created: 1, edited: 10),
            richSheet(81, title: "Other newest", created: 2, edited: 100, folderID: otherFolder),
            richSheet(82, title: "Deleted General", created: 3, edited: 20),
        ]
        let sameGeneral = try fullPlan(generalSheets, 2, 2, .dateEdited)
        try expectEqual(selectedSheetID(afterRemoving: 2, from: generalSheets, plan: sameGeneral),
                        generalSheets[0].id, "nil folder membership is the General group")

        let customDeleted = [
            richSheet(83, title: "Other folder", created: 1, edited: 10, folderID: otherFolder),
            richSheet(84, title: "Deleted custom group", created: 2, edited: 5,
                      folderID: testUUID(9_031)),
            richSheet(85, title: "General newest", created: 3, edited: 30),
        ]
        let fallback = try fullPlan(customDeleted, 1, 1, .dateEdited)
        try expectEqual(selectedSheetID(afterRemoving: 1, from: customDeleted, plan: fallback),
                        customDeleted[2].id, "nil General may also be the global fallback winner")
    },

    EngineCase("deletion-inactive-preserves-selected-sheet-before-or-after") {
        let selectedFolder = testUUID(9_040)
        let deletedFolder = testUUID(9_041)
        let sheets = [
            richSheet(90, title: "Delete before", created: 1, edited: 10,
                      folderID: deletedFolder),
            richSheet(91, title: "Active elsewhere", created: 2, edited: 20,
                      folderID: selectedFolder),
            richSheet(92, title: "Delete after", created: 3, edited: 30,
                      folderID: deletedFolder),
        ]
        let before = try fullPlan(sheets, 0, 1, .dateEdited)
        try expectEqual(before, try plan(sheets.count, 0, 1),
                        "inactive deletion before selection preserves the exact legacy shift plan")
        try expectEqual(selectedSheetID(afterRemoving: 0, from: sheets, plan: before),
                        sheets[1].id, "the active UUID survives deletion before it")
        let after = try fullPlan(sheets, 2, 1, .name)
        try expectEqual(after, try plan(sheets.count, 2, 1),
                        "inactive deletion after selection leaves the active index alone")
        try expectEqual(selectedSheetID(afterRemoving: 2, from: sheets, plan: after),
                        sheets[1].id, "the active UUID survives deletion after it")
    },

    EngineCase("deletion-full-sheet-two-singleton-and-invalid-boundaries") {
        let two = [
            richSheet(100, title: "First", created: 1, edited: 10),
            richSheet(101, title: "Second", created: 2, edited: 20),
        ]
        let deletingFirst = try fullPlan(two, 0, 0, .dateEdited)
        try expectEqual(deletingFirst.selectedIndexAfter, 0, "two-sheet active deletion selects the sole survivor")
        try expectEqual(selectedSheetID(afterRemoving: 0, from: two, plan: deletingFirst),
                        two[1].id, "two-sheet survivor identity is exact")
        let deletingLast = try fullPlan(two, 1, 1, .dateEdited)
        try expectEqual(selectedSheetID(afterRemoving: 1, from: two, plan: deletingLast),
                        two[0].id, "the first sheet survives deletion of the second")

        let one = [richSheet(102, title: "Only", created: 1, edited: 1)]
        let singleton = try fullPlan(one, 0, 0, .name)
        try expectEqual(singleton, try plan(1, 0, 0),
                        "singleton replacement preserves the legacy plan exactly")
        try expect(sheetDeletionPlan(sheets: [], deleteIndex: 0, selectedIndex: 0,
                                     sortOrder: .dateEdited) == nil,
                   "empty sheets return nil before any indexing")
        try expect(sheetDeletionPlan(sheets: two, deleteIndex: -1, selectedIndex: 0,
                                     sortOrder: .dateEdited) == nil,
                   "negative deletion index is rejected")
        try expect(sheetDeletionPlan(sheets: two, deleteIndex: 2, selectedIndex: 0,
                                     sortOrder: .dateEdited) == nil,
                   "deletion index at count is rejected")
        try expect(sheetDeletionPlan(sheets: two, deleteIndex: 0, selectedIndex: 2,
                                     sortOrder: .dateEdited) == nil,
                   "selection index at count is rejected")
    },

    EngineCase("deletion-app-source-contracts-preserve-single-path-and-persist") {
        guard let appModel = deletionSource("Sources/NumlexApp/AppModel.swift"),
              let sidebar = deletionSource("Sources/NumlexApp/Views/SidebarView.swift"),
              let contentView = deletionSource("Sources/NumlexApp/Views/ContentView.swift"),
              let deletion = deletionBody(in: appModel) else {
            throw CaseFailure(message: "AppModel/sidebar/menu deletion sources missing",
                              location: "DeletionCases")
        }
        guard let selectedSnapshot = deletion.range(of: "let deletesSelectedSheet = index == selectedIndex"),
              let removal = deletion.range(of: "sheets.remove(at: index)"),
              let selectedUpdate = deletion.range(of: "selectedIndex = plan.selectedIndexAfter"),
              let groupSync = deletion.range(of: "if deletesSelectedSheet {\n            activeGroup = activeGroup(for: selectedSheet?.folderID)\n        }"),
              let persist = deletion.range(of: "persist()") else {
            throw CaseFailure(message: "deletion must capture selection, remove, select, sync group, and persist",
                              location: "DeletionCases")
        }
        try expect(selectedSnapshot.lowerBound < removal.lowerBound,
                   "active-vs-inactive status is captured before array mutation")
        try expect(deletion.contains("sheetDeletionPlan(sheets: sheets,")
                   && deletion.contains("sortOrder: settings.sidebarSort)"),
                   "the app delegates to the full-sheet planner and current sidebar order")
        try expect(!deletion.contains("sheetDeletionPlan(count:"),
                   "the app does not bypass sorted sheet identity with the legacy helper")
        try expect(selectedUpdate.lowerBound < groupSync.lowerBound
                   && removal.upperBound < groupSync.lowerBound
                   && groupSync.upperBound < persist.lowerBound,
                   "only after mutation and replacement selection does active deletion sync the tab")
        try expectEqual(deletionSourceCount("activeGroup =", in: deletion), 1,
                        "the active-group mutation has one active-deletion guard")
        try expectEqual(deletionSourceCount("persist()", in: deletion), 1,
                        "deletion persists exactly once")
        try expect(!deletion.contains("select(index:"),
                   "deletion does not route through selection and persist a second time")
        try expect(deletion.contains("if plan.replacesSoleSheet")
                   && deletion.contains("freshSheet(in: folder, ordinal: 1)")
                   && deletion.contains("NewSheetTemplate.caretOffset(for: settings.newSheetStart)"),
                   "the existing sole-sheet template and caret path remain shared")
        try expect(deletion.contains("randomStores[sheets[0].id] = nil")
                   && deletion.contains("randomStores[removedID] = nil"),
                   "singleton replacement and ordinary deletion both discard the removed random store")
        try expect(deletion.contains("focusSheetID = replacement.id")
                   && deletion.contains("focusCaret = NewSheetTemplate.caretOffset"),
                   "the preexisting focus request remains in the sole replacement branch")
        try expectEqual(deletionSourceCount("focusSheetID =", in: deletion), 1,
                        "ordinary deletion does not request a new sheet focus")
        try expectEqual(deletionSourceCount("focusCaret =", in: deletion), 1,
                        "ordinary deletion does not reposition the caret")
        try expect(appModel.contains("func deleteSelected() {\n        deleteSheet(at: selectedIndex)\n    }"),
                   "the app menu delegates to the same deletion entry point")
        try expect(sidebar.contains("model.deleteSheet(at: idx)"),
                   "the sidebar passes its global index through the same deletion entry point")
        try expect(contentView.contains("for: .deleteSheet)")
                   && contentView.contains("model.deleteSelected()"),
                   "the delete command notification routes through deleteSelected")
    },

    EngineCase("deletion-documentation-ownership-points-to-published-guides") {
        guard let readme = deletionSource("README.md"),
              let contributor = deletionSource("CONTRIBUTING.md") else {
            throw CaseFailure(message: "README or CONTRIBUTING.md missing",
                              location: "DeletionCases")
        }
        try expect(readme.contains("https://www.numlex.tech/docs/sheets-files/"),
                   "README links directly to the published sheets-and-files guide")
        try expect(readme.contains("Published manuals describe released behavior and may lag `main`")
                   && readme.contains("source code")
                   && readme.contains("tests define the behavior of the current branch."),
                   "README makes source/tests authoritative while published manuals may lag main")
        try expect(contributor.contains("manuals are maintained on the [Numlex documentation site]")
                   && contributor.contains("may lag `main`")
                   && contributor.contains("current source and tests are authoritative."),
                   "contributor guidance assigns manuals to the website and identifies current-main authority")
    },
]
