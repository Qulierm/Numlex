import Foundation

/// r39: a one-level sidebar folder that groups sheets. Identity is the
/// STABLE UUID (manual title duplicates are allowed — the UUID, not the
/// title, is the identity). Membership is recorded on `Sheet.folderID`;
/// a nil membership is the built-in localized General group. Folder
/// organization is app-local: folders never travel in `.nlx` exports.
public struct SheetFolder: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    /// User-editable display title; not unique.
    public var title: String

    public init(id: UUID = UUID(), title: String) {
        self.id = id
        self.title = title
    }
}

/// r39 (r40 semantics): the sidebar's ONE active folder filter
/// (presentation-only, never persisted): the built-in General group or
/// one custom folder. During normal UI it is always `.general` or
/// `.folder(validID)` — the upper sheet list shows exactly the sheets
/// of the active tab. `.none` remains only as a compatibility fallback
/// (it maps to General everywhere it matters).
public enum SidebarGroup: Equatable, Sendable {
    case none
    case general
    case folder(UUID)
}

/// r39: pure, unit-testable folder-organization logic. The app model
/// calls these and persists; every rule (sanitize, generated naming,
/// move, delete-unfile, insertion point) lives here so the regression
/// tests cover the behavior without touching any UI.
public enum SheetOrganization {
    /// Repairs a persisted folder/sheet state that may be corrupt:
    /// - duplicate folder UUIDs are collapsed to the FIRST occurrence
    ///   (later duplicates are dropped; sheets keep their membership —
    ///   the surviving folder carries the same id),
    /// - every `sheet.folderID` is either nil or the id of a surviving
    ///   folder (orphans become nil = General),
    /// - folder order and sheet order are preserved and sheet content
    ///   is never touched.
    public static func sanitize(folders: [SheetFolder],
                                sheets: [Sheet]) -> (folders: [SheetFolder], sheets: [Sheet]) {
        var seen = Set<UUID>()
        let surviving = folders.filter { seen.insert($0.id).inserted }
        let ids = Set(surviving.map(\.id))
        let repaired = sheets.map { sheet in
            guard let fid = sheet.folderID, !ids.contains(fid) else { return sheet }
            var s = sheet
            s.folderID = nil
            return s
        }
        return (surviving, repaired)
    }

    /// The generated, localized, unique default folder name: the base
    /// (`New Folder` in the current language), then `New Folder 2`, …
    /// — never an exact match for an existing title.
    public static func generatedFolderName(existing: [String], language: AppLanguage) -> String {
        let base = L10n.t("newFolder", language: language)
        let taken = Set(existing)
        var n = 1
        var candidate = base
        while taken.contains(candidate) {
            n += 1
            candidate = "\(base) \(n)"
        }
        return candidate
    }

    /// The global index a new sheet is inserted at to appear at the TOP
    /// of its rendered group (General is nil): before the group's first
    /// sheet in global order, or 0 when the group is empty.
    public static func insertionIndex(forGroup groupID: UUID?, in sheets: [Sheet]) -> Int {
        sheets.firstIndex { $0.folderID == groupID } ?? 0
    }

    /// Moves one sheet by STABLE ID to a folder (nil = General).
    /// Returns true only when membership actually changed; sheet order
    /// and every other field are untouched.
    @discardableResult
    public static func moveSheet(_ sheets: inout [Sheet], id: UUID, to folderID: UUID?) -> Bool {
        guard let i = sheets.firstIndex(where: { $0.id == id }) else { return false }
        guard sheets[i].folderID != folderID else { return false }
        sheets[i].folderID = folderID
        return true
    }

    /// Removes a folder and safely unfiles its members to General: no
    /// sheet is ever deleted, sheet order is preserved. Returns true
    /// when a folder with that id existed.
    @discardableResult
    public static func removeFolder(_ folders: inout [SheetFolder], id: UUID,
                                    sheets: inout [Sheet]) -> Bool {
        guard folders.contains(where: { $0.id == id }) else { return false }
        for i in sheets.indices where sheets[i].folderID == id {
            sheets[i].folderID = nil
        }
        folders.removeAll { $0.id == id }
        return true
    }

    // MARK: r40 tab-filter helpers

    /// The folder ID a sidebar group filters on: the custom folder's id,
    /// or nil for General (the `.none` fallback maps to General).
    public static func folderID(of group: SidebarGroup) -> UUID? {
        if case .folder(let id) = group { return id }
        return nil
    }

    /// The global-order sheets of one tab (nil = General): membership
    /// filtered, order NEVER reordered — the upper list renders exactly
    /// these pairs (global index + sheet) so selection and deletion keep
    /// the global guarantees.
    public static func visibleSheets(_ sheets: [Sheet], folderID: UUID?) -> [Sheet] {
        sheets.filter { $0.folderID == folderID }
    }

    /// The index a NEW folder is inserted at when it is created "after"
    /// a reference tab (the hover-plus insertion order):
    /// - after General (nil) => 0 — the new folder becomes the FIRST
    ///   custom folder,
    /// - after an existing custom folder => immediately after it,
    /// - after a stale/unknown id => appended at the end (safe fallback;
    ///   with an empty list that is also 0).
    public static func folderInsertionIndex(afterID folderID: UUID?,
                                            in folders: [SheetFolder]) -> Int {
        if let id = folderID,
           let i = folders.firstIndex(where: { $0.id == id }) {
            return i + 1
        }
        return folderID == nil ? 0 : folders.count
    }
}
