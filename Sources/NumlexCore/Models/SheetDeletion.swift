/// Pure selection plan for deleting one sheet from a list. This is the
/// only state math the deletion feature has, extracted so it is
/// testable without the app model:
///
/// - deleting BEFORE the selection shifts the list but the SAME sheet
///   stays selected,
/// - deleting the SELECTED sheet selects the sheet that takes its slot
///   (the next one, or the previous one when the selected row was last),
/// - deleting a sheet after the selection changes nothing about which
///   sheet is selected,
/// - the SOLE sheet is never removed: the caller replaces it in place
///   with a fresh empty sheet and keeps selection at 0.
public struct SheetDeletionPlan: Equatable, Sendable {
    public let deleteIndex: Int
    public let selectedIndexAfter: Int
    public let replacesSoleSheet: Bool
    public init(deleteIndex: Int, selectedIndexAfter: Int, replacesSoleSheet: Bool) {
        self.deleteIndex = deleteIndex
        self.selectedIndexAfter = selectedIndexAfter
        self.replacesSoleSheet = replacesSoleSheet
    }
}

/// `nil` when either index is outside the (non-empty) list.
public func sheetDeletionPlan(count: Int,
                              deleteIndex: Int,
                              selectedIndex: Int) -> SheetDeletionPlan? {
    guard count > 0,
          (0..<count).contains(deleteIndex),
          (0..<count).contains(selectedIndex) else { return nil }
    if count == 1 {
        return SheetDeletionPlan(deleteIndex: 0, selectedIndexAfter: 0,
                                 replacesSoleSheet: true)
    }
    let selectedIndexAfter: Int
    switch (deleteIndex, selectedIndex) {
    case let (d, s) where d < s:
        // The selected sheet shifted down by one; follow it.
        selectedIndexAfter = s - 1
    case let (d, s) where d == s:
        // The next sheet takes the slot; at the end there is no next,
        // so the previous one stays selected.
        selectedIndexAfter = min(s, count - 2)
    default:
        // Deleted after the selection: nothing moves over it.
        selectedIndexAfter = selectedIndex
    }
    return SheetDeletionPlan(deleteIndex: deleteIndex,
                             selectedIndexAfter: selectedIndexAfter,
                             replacesSoleSheet: false)
}
