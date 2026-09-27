import Foundation

/// The pure, unit-tested Sheet Behavior contracts (General Settings):
/// what a process launch selects, what a freshly created sheet starts
/// with, and the sidebar's presentation order. None of these helpers
/// mutate persisted state — the model applies their results.
public enum SheetLaunch {

    /// The index a launch selects for the configured behavior.
    ///
    /// * `.lastEdited` picks the sheet with the greatest `modifiedAt`.
    ///   Ties keep the persisted selection when it is one of the tied
    ///   sheets (so a deliberate selection survives a coincidental
    ///   timestamp collision); otherwise the FIRST tied sheet in stable
    ///   global order wins.
    /// * `.newSheet` keeps the restored selection — the caller then
    ///   creates the launch sheet in that sheet's folder.
    ///
    /// An empty list always resolves to 0.
    public static func initialSelection(behavior: LaunchSheetBehavior,
                                        sheets: [Sheet],
                                        persistedIndex: Int) -> Int {
        guard !sheets.isEmpty else { return 0 }
        let clamped = min(max(persistedIndex, 0), sheets.count - 1)
        switch behavior {
        case .newSheet:
            return clamped
        case .lastEdited:
            guard let newest = sheets.map(\.modifiedAt).max() else { return 0 }
            let tied = sheets.enumerated()
                .filter { $0.element.modifiedAt == newest }
                .map(\.offset)
            if tied.contains(clamped) { return clamped }
            return tied.first ?? 0
        }
    }
}

/// The content and caret contract of a freshly created sheet. ONE source
/// of truth for toolbar/menu/folder creation, the launch sheet and the
/// sole-sheet replacement; sheet IMPORTS never go through this path.
public enum NewSheetTemplate {

    /// The initial content of a new sheet. Empty for a regular line, and
    /// exactly `# ` (hash + one space) for a heading — one logical line,
    /// so the sheet carries exactly one stable line ID.
    public static func content(for start: NewSheetStart) -> String {
        switch start {
        case .regularLine: return ""
        case .heading: return "# "
        }
    }

    /// The UTF-16 caret offset the editor should adopt for the fresh
    /// sheet: 0 for a regular line, 2 (after `# `) for a heading so the
    /// user keeps typing the heading text.
    public static func caretOffset(for start: NewSheetStart) -> Int {
        switch start {
        case .regularLine: return 0
        case .heading: return 2
        }
    }
}

/// The sidebar's presentation order inside one folder. Purely
/// presentational: entries carry their GLOBAL index, the returned array is
/// a reordering of the same pairs, and `model.sheets` is never touched —
/// selection, deletion, folder movement, tokens and persistence keep
/// their global-index identity.
public enum SheetSorting {

    /// Sorts `(global index, sheet)` pairs for display. Date orders are
    /// newest-first, Name is the localized-standard ascending title
    /// compare, and EVERY order falls back to the global index, so the
    /// result is a deterministic total order (no unstable-sort surprises).
    public static func sorted(_ entries: [(index: Int, sheet: Sheet)],
                              by order: SidebarSortOrder) -> [(index: Int, sheet: Sheet)] {
        entries.sorted { a, b in
            switch order {
            case .dateEdited:
                if a.sheet.modifiedAt != b.sheet.modifiedAt {
                    return a.sheet.modifiedAt > b.sheet.modifiedAt
                }
            case .dateCreated:
                if a.sheet.createdAt != b.sheet.createdAt {
                    return a.sheet.createdAt > b.sheet.createdAt
                }
            case .name:
                let comparison = a.sheet.title.localizedStandardCompare(b.sheet.title)
                if comparison != .orderedSame {
                    return comparison == .orderedAscending
                }
            }
            return a.index < b.index
        }
    }
}
