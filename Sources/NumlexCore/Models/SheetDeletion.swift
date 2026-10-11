/// Pure selection-plan result shared by the legacy index-only helper and
/// the sidebar-order-aware full-sheet helper. The caller performs removal or
/// the established sole-sheet replacement; planning never mutates sheets.
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

/// Compatibility planning for callers that know only the array count. It
/// retains the historical slot/neighbor selection semantics. App deletion
/// should use the full-sheet overload so an active deletion follows the
/// configured sidebar order within the deleted sheet's folder.
public func sheetDeletionPlan(sheets: [Sheet],
                              deleteIndex: Int,
                              selectedIndex: Int,
                              sortOrder: SidebarSortOrder) -> SheetDeletionPlan? {
    // Reuse the legacy validation and preserve its exact result for a
    // nonselected deletion or the established sole-sheet replacement.
    guard let legacyPlan = sheetDeletionPlan(count: sheets.count,
                                            deleteIndex: deleteIndex,
                                            selectedIndex: selectedIndex) else {
        return nil
    }
    guard !legacyPlan.replacesSoleSheet, deleteIndex == selectedIndex else {
        return legacyPlan
    }

    let deletedFolderID = sheets[deleteIndex].folderID
    let remaining = sheets.enumerated()
        .filter { $0.offset != deleteIndex }
        .map { (index: $0.offset, sheet: $0.element) }
    let sameFolder = remaining.filter { $0.sheet.folderID == deletedFolderID }
    let preferred = SheetSorting.sorted(sameFolder, by: sortOrder).first
        ?? SheetSorting.sorted(remaining, by: sortOrder).first

    // The validated nonsingleton case always has at least one survivor.
    // Retain the legacy result defensively if this contract ever changes.
    guard let survivor = preferred else { return legacyPlan }
    let selectedIndexAfter = survivor.index > deleteIndex
        ? survivor.index - 1
        : survivor.index
    return SheetDeletionPlan(deleteIndex: deleteIndex,
                             selectedIndexAfter: selectedIndexAfter,
                             replacesSoleSheet: false)
}
