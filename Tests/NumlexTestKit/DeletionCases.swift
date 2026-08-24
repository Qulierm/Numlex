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
]
