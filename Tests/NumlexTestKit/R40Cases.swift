import Foundation
import NumlexCore

/// r40: sidebar folder TABS — the pure tab-filter logic: hover-plus
/// insertion order (after General / after a custom folder / stale
/// reference), folder order persistence, the SidebarGroup-to-folder-ID
/// mapping, and the visible-list filter (membership without reordering
/// the global sheet array).
public let r40Cases: [EngineCase] = [
    EngineCase("r40-folder-insert-after-general") {
        // General's plus creates the FIRST custom folder: index 0.
        try expectEqual(SheetOrganization.folderInsertionIndex(afterID: nil, in: []),
                        0, "after General into an empty list is 0")
        let a = SheetFolder(id: UUID(), title: "A")
        let b = SheetFolder(id: UUID(), title: "B")
        try expectEqual(SheetOrganization.folderInsertionIndex(afterID: nil,
                                                               in: [a, b]),
                        0, "after General is always before every custom folder")
        // The .none fallback also maps to the General rule.
        try expectEqual(SheetOrganization.folderInsertionIndex(
            afterID: SheetOrganization.folderID(of: .none), in: [a, b]),
            0, ".none falls back to the General rule")
    },
    EngineCase("r40-folder-insert-after-custom") {
        let a = SheetFolder(id: UUID(), title: "A")
        let b = SheetFolder(id: UUID(), title: "B")
        let c = SheetFolder(id: UUID(), title: "C")
        try expectEqual(SheetOrganization.folderInsertionIndex(afterID: a.id,
                                                               in: [a, b, c]),
                        1, "after A => immediately after A")
        try expectEqual(SheetOrganization.folderInsertionIndex(afterID: c.id,
                                                               in: [a, b, c]),
                        3, "after the last folder => append")
        try expectEqual(SheetOrganization.folderInsertionIndex(afterID: b.id,
                                                               in: [b]),
                        1, "after the only folder => append")
    },
    EngineCase("r40-folder-insert-stale-appends") {
        let a = SheetFolder(id: UUID(), title: "A")
        let stale = UUID()
        try expectEqual(SheetOrganization.folderInsertionIndex(afterID: stale,
                                                               in: [a]),
                        1, "a stale reference appends instead of crashing")
        try expectEqual(SheetOrganization.folderInsertionIndex(afterID: stale, in: []),
                        0, "a stale reference into an empty list is 0")
    },
    EngineCase("r40-folder-order-persists") {
        // Create a, then hover-plus after General (new becomes first),
        // then hover-plus after a: the persisted ORDER must be exactly
        // the created order.
        let a = SheetFolder(id: UUID(uuidString: "71111111-1111-1111-1111-111111111111")!,
                            title: "First")
        let early = SheetFolder(id: UUID(uuidString: "72222222-2222-2222-2222-222222222222")!,
                                title: "Second")
        let late = SheetFolder(id: UUID(uuidString: "73333333-3333-3333-3333-333333333333")!,
                               title: "Third")
        var folders = [a]
        folders.insert(early,
                       at: SheetOrganization.folderInsertionIndex(afterID: nil, in: folders))
        folders.insert(late,
                       at: SheetOrganization.folderInsertionIndex(afterID: a.id, in: folders))
        let p = StorePayload(sheets: [], selectedIndex: 0, settings: .defaults,
                             version: 2, folders: folders)
        let p2 = try JSONDecoder().decode(StorePayload.self, from: JSONEncoder().encode(p))
        try expectEqual(p2.folders.map(\.id),
                        [early.id, a.id, late.id],
                        "insertion order survives the store roundtrip")
    },
    EngineCase("r40-group-id-mapping") {
        let id = UUID()
        try expectEqual(SheetOrganization.folderID(of: .general), nil,
                        "General filters on nil")
        try expectEqual(SheetOrganization.folderID(of: .none), nil,
                        ".none maps to the General filter")
        try expectEqual(SheetOrganization.folderID(of: .folder(id)), id,
                        "a folder tab filters on its id")
    },
    EngineCase("r40-visible-filtering-preserves-global-order") {
        let f = SheetFolder(id: UUID(uuidString: "74444444-4444-4444-4444-444444444444")!,
                            title: "Work")
        let g = SheetFolder(id: UUID(uuidString: "75555555-5555-5555-5555-555555555555")!,
                            title: "Home")
        var s1 = Sheet(title: "s1", content: "1")          // General
        var s2 = Sheet(title: "s2", content: "2")
        s2.folderID = f.id
        var s3 = Sheet(title: "s3", content: "3")          // General
        var s4 = Sheet(title: "s4", content: "4")
        s4.folderID = g.id
        var s5 = Sheet(title: "s5", content: "5")
        s5.folderID = f.id
        let all = [s1, s2, s3, s4, s5]
        try expectEqual(SheetOrganization.visibleSheets(all, folderID: nil).map(\.id),
                        [s1.id, s3.id],
                        "General shows the unfiled sheets in global order")
        try expectEqual(SheetOrganization.visibleSheets(all, folderID: f.id).map(\.id),
                        [s2.id, s5.id],
                        "a custom tab shows its members in global order")
        try expectEqual(SheetOrganization.visibleSheets(all, folderID: g.id).map(\.id),
                        [s4.id],
                        "single-member tab")
        try expectEqual(SheetOrganization.visibleSheets(all, folderID: UUID()).map(\.id),
                        [],
                        "an unknown folder tab is empty")
    },
]
