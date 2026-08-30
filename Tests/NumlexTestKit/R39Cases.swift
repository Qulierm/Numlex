import Foundation
import NumlexCore

/// r39: one-level sidebar folders — Sheet.folderID stability,
/// additive/backward-compatible StorePayload decoding (missing and
/// malformed folder fields), the pure organization logic (sanitize,
/// generated localized names, insertion point, move, delete-unfile)
/// and the `.nlx` export boundary (no folder metadata).
public let r39Cases: [EngineCase] = [
    EngineCase("r39-sheet-folderid-missing-and-roundtrip") {
        // A pre-r39 sheet JSON without the folderID key decodes to nil
        // (General), siblings untouched.
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111","title":"Sheet","content":"1 + 1",
         "createdAt":700000000,"modifiedAt":700000000,"isTitleCustom":false,"titleSeed":"Sheet",
         "lineIDs":["22222222-2222-2222-2222-222222222222","33333333-3333-3333-3333-333333333333"],
         "references":[]}
        """
        let s = try JSONDecoder().decode(Sheet.self, from: Data(json.utf8))
        try expectEqual(s.folderID, nil, "missing key decodes to General (nil)")
        try expectEqual(s.title, "Sheet")
        try expectEqual(s.content, "1 + 1")
        // The fresh initializer defaults to General.
        try expectEqual(Sheet(title: "Sheet", content: "").folderID, nil)
        // Full roundtrip of a FILED sheet keeps the membership.
        let fid = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        var filed = Sheet(title: "Sheet", content: "2 + 2")
        filed.folderID = fid
        let back = try JSONDecoder().decode(Sheet.self, from: JSONEncoder().encode(filed))
        try expectEqual(back.folderID, fid, "filed membership survives the roundtrip")
        try expectEqual(back.content, "2 + 2")
        // And a General sheet roundtrips without the key being invented.
        let general = Sheet(title: "Sheet", content: "3 + 3")
        let back2 = try JSONDecoder().decode(Sheet.self, from: JSONEncoder().encode(general))
        try expectEqual(back2.folderID, nil)
    },
    EngineCase("r39-sheet-folderid-wrong-type") {
        // A wrong-typed folderID (string where a UUID is expected) must
        // fall back to General without failing the whole sheet.
        let bad = """
        {"id":"11111111-1111-1111-1111-111111111111","title":"Sheet","content":"1 + 1",
         "createdAt":700000000,"modifiedAt":700000000,"folderID":"not-a-uuid"}
        """
        let s = try JSONDecoder().decode(Sheet.self, from: Data(bad.utf8))
        try expectEqual(s.folderID, nil, "wrong type falls back to General")
        try expectEqual(s.content, "1 + 1", "the rest of the sheet decodes")
    },
    EngineCase("r39-store-legacy-missing-folders") {
        // A v2 payload with no `folders` key at all decodes to [].
        let json = """
        {"sheets":[],"selectedIndex":0,
         "settings":{"decimalPlaces":7,"fontSizeKey":"ts","language":"ru","sheetName":"S","lineNumbers":false,"fontColor":"white"},
         "version":2}
        """
        let p = try JSONDecoder().decode(StorePayload.self, from: Data(json.utf8))
        try expectEqual(p.folders, [], "legacy store decodes [] folders")
        try expectEqual(p.version, 2)
        try expectEqual(p.settings.decimalPlaces, 7)
        // A malformed `folders` field must NOT discard the rest of the
        // otherwise valid store.
        let bad = """
        {"sheets":[],"selectedIndex":0,
         "settings":{"decimalPlaces":7,"fontSizeKey":"ts","language":"ru","sheetName":"S","lineNumbers":false,"fontColor":"white"},
         "version":2,"folders":"oops"}
        """
        let p2 = try JSONDecoder().decode(StorePayload.self, from: Data(bad.utf8))
        try expectEqual(p2.folders, [], "malformed folder field decodes []")
        try expectEqual(p2.settings.sheetName, "S", "the rest of the store survives")
        try expectEqual(p2.selectedIndex, 0)
    },
    EngineCase("r39-folder-full-roundtrip") {
        let f1 = SheetFolder(id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
                              title: "Work")
        let f2 = SheetFolder(id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
                              title: "Home")
        var a = Sheet(title: "A", content: "1 + 1")
        a.folderID = f2.id
        let b = Sheet(title: "B", content: "2 + 2") // General
        let p = StorePayload(sheets: [a, b], selectedIndex: 1, settings: .defaults,
                             version: 2, folders: [f1, f2])
        let p2 = try JSONDecoder().decode(StorePayload.self, from: JSONEncoder().encode(p))
        try expectEqual(p2.folders, p.folders, "folders survive the roundtrip in order")
        try expectEqual(p2.sheets, p.sheets, "sheet membership survives the roundtrip")
        try expectEqual(p2.selectedIndex, 1)
        try expectEqual(p2.version, 2)
        try expectEqual(p2.sheets[0].folderID, f2.id)
        try expectEqual(p2.sheets[1].folderID, nil)
    },
    EngineCase("r39-folder-sanitize-orphan") {
        // A sheet pointing at a folder that does not exist is unfiled
        // to General; content and order are untouched.
        let f1 = SheetFolder(id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
                              title: "Work")
        var orphaned = Sheet(title: "O", content: "7 + 7")
        orphaned.folderID = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
        let kept = Sheet(title: "K", content: "8 + 8")
        let (folders, sheets) = SheetOrganization.sanitize(
            folders: [f1], sheets: [orphaned, kept])
        try expectEqual(folders, [f1], "the real folder survives")
        try expectEqual(sheets[0].folderID, nil, "orphan membership becomes General")
        try expectEqual(sheets[0].content, "7 + 7", "content is never touched")
        try expectEqual(sheets.map(\.id), [orphaned.id, kept.id], "sheet order preserved")
    },
    EngineCase("r39-folder-duplicate-uuid-repair") {
        // Two folder entries with the SAME UUID collapse to the first;
        // sheets keep their membership (the surviving folder carries
        // the same id), order is preserved.
        let id = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let first = SheetFolder(id: id, title: "Work")
        let dupe = SheetFolder(id: id, title: "Work Copy")
        let other = SheetFolder(id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
                                title: "Home")
        var member = Sheet(title: "M", content: "1 + 2")
        member.folderID = id
        let (folders, sheets) = SheetOrganization.sanitize(
            folders: [first, dupe, other], sheets: [member])
        try expectEqual(folders.map(\.id), [id, other.id], "first occurrence survives")
        try expectEqual(folders[0].title, "Work", "the FIRST entry's title wins")
        try expectEqual(sheets[0].folderID, id, "membership stays valid after the dedupe")
        try expectEqual(sheets[0].content, "1 + 2")
    },
    EngineCase("r39-folder-generated-names") {
        try expectEqual(SheetOrganization.generatedFolderName(existing: [], language: .en),
                        "New Folder")
        try expectEqual(SheetOrganization.generatedFolderName(existing: ["New Folder"], language: .en),
                        "New Folder 2")
        try expectEqual(SheetOrganization.generatedFolderName(
            existing: ["New Folder", "New Folder 2", "Other"], language: .en),
            "New Folder 3")
        // Localized bases in other languages, same uniqueness rule.
        try expectEqual(SheetOrganization.generatedFolderName(existing: [], language: .ru),
                        "Новая папка")
        try expectEqual(SheetOrganization.generatedFolderName(
            existing: ["Новая папка"], language: .ru),
            "Новая папка 2")
        try expectEqual(SheetOrganization.generatedFolderName(existing: [], language: .zh),
                        "新建文件夹")
    },
    EngineCase("r39-folder-insertion-index") {
        let f1 = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        var g0 = Sheet(title: "G0", content: "")
        var f1a = Sheet(title: "F1a", content: "")
        f1a.folderID = f1
        var g1 = Sheet(title: "G1", content: "")
        var f1b = Sheet(title: "F1b", content: "")
        f1b.folderID = f1
        let sheets = [g0, f1a, g1, f1b]
        // Top of folder F1 = before its first sheet in global order.
        try expectEqual(SheetOrganization.insertionIndex(forGroup: f1, in: sheets), 1)
        // Top of General = before its first sheet.
        try expectEqual(SheetOrganization.insertionIndex(forGroup: nil, in: sheets), 0)
        // An empty group inserts at 0 (it renders alone at the top).
        try expectEqual(SheetOrganization.insertionIndex(
            forGroup: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
            in: sheets), 0)
        // Inserting at the returned index puts the new sheet FIRST in
        // its rendered group.
        var new = Sheet(title: "New", content: "")
        var moved = sheets
        new.folderID = f1
        moved.insert(new, at: SheetOrganization.insertionIndex(forGroup: f1, in: moved))
        let groupOrder = moved.filter { $0.folderID == f1 }.map(\.title)
        try expectEqual(groupOrder, ["New", "F1a", "F1b"])
        // And global order of the other sheets is preserved.
        try expectEqual(moved.filter { $0.folderID == nil }.map(\.title), ["G0", "G1"])
    },
    EngineCase("r39-folder-move-plans") {
        let f1 = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let f2 = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        var a = Sheet(title: "A", content: "1 + 1")          // General
        var b = Sheet(title: "B", content: "2 + 2")
        b.folderID = f1
        var c = Sheet(title: "C", content: "3 + 3")
        c.folderID = f2
        var sheets = [a, b, c]
        // General -> folder: exactly the moved sheet changes.
        try expect(SheetOrganization.moveSheet(&sheets, id: a.id, to: f1),
                   "a real move reports success")
        try expectEqual(sheets[0].folderID, f1)
        try expectEqual(sheets.map(\.id), [a.id, b.id, c.id], "order untouched")
        try expectEqual(sheets[2].folderID, f2, "other sheets untouched")
        // Folder -> folder.
        try expect(SheetOrganization.moveSheet(&sheets, id: a.id, to: f2))
        try expectEqual(sheets[0].folderID, f2)
        // Folder -> General.
        try expect(SheetOrganization.moveSheet(&sheets, id: a.id, to: nil))
        try expectEqual(sheets[0].folderID, nil)
        // Moving to the CURRENT group is a no-op.
        try expect(!SheetOrganization.moveSheet(&sheets, id: b.id, to: f1),
                   "same-group move is a no-op")
        // An unknown id is a no-op.
        try expect(!SheetOrganization.moveSheet(
            &sheets, id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!, to: f1))
        // Content is never touched by any of the moves.
        try expectEqual(sheets.map(\.content), ["1 + 1", "2 + 2", "3 + 3"])
    },
    EngineCase("r39-folder-delete-unfiles") {
        let f1 = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let f2 = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let folders = [SheetFolder(id: f1, title: "Work"),
                       SheetFolder(id: f2, title: "Home")]
        var a = Sheet(title: "A", content: "1 + 1"); a.folderID = f1
        let b = Sheet(title: "B", content: "2 + 2")            // General
        var c = Sheet(title: "C", content: "3 + 3"); c.folderID = f1
        var d = Sheet(title: "D", content: "4 + 4"); d.folderID = f2
        var list = [a, b, c, d]
        var all = folders
        // Deleting a folder unfiles EVERY member to General: no sheet
        // is lost, order and content stay put.
        try expect(SheetOrganization.removeFolder(&all, id: f1, sheets: &list))
        try expectEqual(list.map(\.id), [a.id, b.id, c.id, d.id], "no sheet deleted")
        try expectEqual(list.map { $0.folderID }, [nil, nil, nil, f2], "members unfiled to General")
        try expectEqual(list.map(\.content), ["1 + 1", "2 + 2", "3 + 3", "4 + 4"])
        try expectEqual(all.map(\.id), [f2], "the other folder survives in order")
        // Deleting an unknown folder is a no-op.
        try expect(!SheetOrganization.removeFolder(
            &all, id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!, sheets: &list))
        try expectEqual(list.count, 4)
    },
    EngineCase("r39-export-has-no-folder-key") {
        // SheetExport is the `.nlx` boundary: it must never carry
        // folder metadata in either direction.
        var exported = SheetExport(title: "T", content: "1 + 1")
        exported.isTitleCustom = true
        let data = try JSONEncoder().encode(exported)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let keys = Set(json.keys)
        try expect(!keys.contains("folderID"), "no folderID key in the export")
        try expect(!keys.contains("folders"), "no folders key in the export")
        try expectEqual(keys, ["title", "content", "isTitleCustom"],
                        "only the long-standing export keys are present")
        // And a legacy export (no optional keys) still decodes.
        let legacy = Data("""
        {"title":"T","content":"1 + 1"}
        """.utf8)
        let obj = try JSONDecoder().decode(SheetExport.self, from: legacy)
        try expectEqual(obj.title, "T")
        try expectEqual(obj.isTitleCustom, nil)
    }
]
