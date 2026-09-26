import Foundation
import NumlexCore

/// Portable `.nlx` snapshot and suggested-filename contracts shared by the
/// standalone runner and Swift Testing.
private func sheetExportAppSource(_ relativePath: String) -> String? {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // NumlexTestKit
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repository root
    let url = root.appendingPathComponent(relativePath).standardizedFileURL
    return try? String(contentsOf: url, encoding: .utf8)
}

public let sheetExportCases: [EngineCase] = [
    EngineCase("sheet-export-snapshot-captures-portable-fields-only") {
        let lineIDs = [
            UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        ]
        let reference = AnswerReference(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            sourceLineID: lineIDs[0], labelLine: 1, location: 6)
        let display = AnswerDisplayPreference(
            lineID: lineIDs[0], decimalPlaces: 3, notation: .scientific)
        let highlight = LineHighlightPreference(lineID: lineIDs[1], color: .blue)
        let folderID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let content = "1 + 1\n\(answerTokenMarker) + 2"
        let sheet = Sheet(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            title: "Portable", content: content,
            createdAt: Date(timeIntervalSince1970: 1),
            modifiedAt: Date(timeIntervalSince1970: 2),
            isTitleCustom: true, titleSeed: "Local seed",
            lineIDs: lineIDs, references: [reference], folderID: folderID,
            answerDisplay: [display], highlights: [highlight])

        let snapshot = SheetExport(snapshotOf: sheet)
        try expectEqual(snapshot.title, "Portable")
        try expectEqual(snapshot.content, content)
        try expectEqual(snapshot.isTitleCustom, true)
        try expectEqual(snapshot.lineIDs, lineIDs)
        try expectEqual(snapshot.references, [reference])
        try expectEqual(snapshot.answerDisplay, [display])
        try expectEqual(snapshot.highlights, [highlight])

        let data = try JSONEncoder().encode(snapshot)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        try expectEqual(Set(object.keys), [
            "title", "content", "isTitleCustom", "lineIDs", "references",
            "answerDisplay", "highlights"
        ], "encoded schema remains the existing SheetExport boundary")
        for excluded in [
            "id", "createdAt", "modifiedAt", "titleSeed", "folderID", "folders",
            "settings", "appearance", "styling", "language"
        ] {
            try expect(object[excluded] == nil, "\(excluded) must not enter .nlx")
        }
    },
    EngineCase("sheet-export-filename-ordinary-and-hostile-characters") {
        try expectEqual(SheetExport.suggestedFilename(for: "Quarterly totals"),
                        "Quarterly totals.nlx")
        try expectEqual(SheetExport.suggestedFilename(for: " Plan/Q1: Draft "),
                        "Plan-Q1- Draft.nlx")
        try expectEqual(SheetExport.suggestedFilename(for: " A\nB\u{0000}C "),
                        "A-B-C.nlx")
        let hostile = SheetExport.suggestedFilename(for: "a/b:c\n")
        try expect(!hostile.contains("/"), "filename is one path component")
        try expect(!hostile.contains(":"), "Finder-hostile colon is replaced")
        try expect(!hostile.unicodeScalars.contains(where: {
            CharacterSet.controlCharacters.contains($0)
        }), "control characters are replaced")
    },
    EngineCase("sheet-export-filename-fallback-hidden-and-existing-suffix") {
        try expectEqual(SheetExport.suggestedFilename(for: " \n\t "), "Sheet.nlx")
        try expectEqual(SheetExport.suggestedFilename(for: "."), "Sheet.nlx")
        try expectEqual(SheetExport.suggestedFilename(for: ".."), "Sheet.nlx")
        try expectEqual(SheetExport.suggestedFilename(for: "Report.NLX"), "Report.nlx")
        try expectEqual(SheetExport.suggestedFilename(for: ".private"), "-private.nlx")
        let name = SheetExport.suggestedFilename(for: ".nlx")
        try expectEqual(name, "Sheet.nlx")
        try expect(!name.hasPrefix("."), "suggested filename is never hidden")
        try expectEqual(name.lowercased().components(separatedBy: ".nlx").count - 1, 1,
                        "exactly one .nlx suffix")
    },
    EngineCase("sheet-export-filename-unicode-and-length-bound") {
        try expectEqual(SheetExport.suggestedFilename(for: " 预算 📈 "), "预算 📈.nlx")
        let longBase = String(repeating: "e\u{301}", count: 121)
        let filename = SheetExport.suggestedFilename(for: longBase)
        try expect(filename.hasSuffix(".nlx"))
        let base = String(filename.dropLast(4))
        try expectEqual(base.count, 120, "base is bounded by grapheme clusters")
        try expectEqual(base, String(longBase.prefix(120)), "Unicode clusters are not split")
    },
    EngineCase("sheet-export-suggested-base-is-extensionless-and-safe") {
        // Receivers that append the type's extension themselves (Finder,
        // via NSItemProvider.suggestedName) need the extensionless base.
        try expectEqual(SheetExport.suggestedFileBase(for: "Quarterly totals"),
                        "Quarterly totals")
        try expectEqual(SheetExport.suggestedFileBase(for: "Report.nlx"), "Report")
        try expectEqual(SheetExport.suggestedFileBase(for: "Report.NLX"), "Report")
        try expectEqual(SheetExport.suggestedFileBase(for: "  \n "), "Sheet")
        try expectEqual(SheetExport.suggestedFileBase(for: ".."), "Sheet")
        try expectEqual(SheetExport.suggestedFileBase(for: ".nlx"), "Sheet")
        try expectEqual(SheetExport.suggestedFileBase(for: ".hidden"), "-hidden")
        try expect(!SheetExport.suggestedFileBase(for: "Plan/2026:Q1").contains("/"),
                   "base stays one path component")
        try expect(!SheetExport.suggestedFileBase(for: "x").hasSuffix(".nlx"),
                   "the base never carries the export suffix")
        try expectEqual(SheetExport.suggestedFileBase(for: "Report") + ".nlx",
                        SheetExport.suggestedFilename(for: "Report"),
                        "the full name is exactly base + one suffix")
    },
    EngineCase("sheet-drag-source-captures-concrete-sheet-snapshot") {
        guard let source = sheetExportAppSource("Sources/NumlexApp/Views/SidebarView.swift") else {
            throw CaseFailure(message: "SidebarView source missing")
        }
        try expect(source.contains(".draggable(SheetDragItem(source: sheet))"),
                   "the row passes its concrete sheet into the drag value")
        try expect(source.contains("init(source sheet: Sheet)"),
                   "source-created drag initializer exists")
        try expect(source.contains("exportSnapshot = SheetExport(snapshotOf: sheet)"),
                   "the immutable portable snapshot is captured at drag creation")
        try expect(source.contains("let base = SheetExport.suggestedFileBase(for: sheet.title)"),
                   "the suggested name is captured once from the same sheet")
        try expect(source.contains("exportFilename = base + \".nlx\""),
                   "the staged file carries exactly one .nlx suffix")
        try expect(source.contains("exportSuggestedName = base"),
                   "the receiver-facing suggestion stays extensionless")
        try expect(!source.contains("SheetDragItem(sheetID: sheet.id)"),
                   "the old ID-only drag source is gone")
    },
    EngineCase("sheet-drag-has-private-uuid-and-file-representations") {
        guard let source = sheetExportAppSource("Sources/NumlexApp/Views/SidebarView.swift"),
              let itemStart = source.range(of: "struct SheetDragItem:"),
              let itemEnd = source.range(of: "extension UTType", range: itemStart.upperBound..<source.endIndex)
        else {
            throw CaseFailure(message: "SheetDragItem source block missing")
        }
        let item = String(source[itemStart.lowerBound..<itemEnd.lowerBound])
        try expect(item.contains("CodableRepresentation(contentType: .numlexSheetMove)"),
                   "folder moves keep the private representation")
        try expect(item.contains("FileRepresentation(exportedContentType: .nlx)"),
                   "Finder receives a real NLX file representation")
        try expect(item.contains("private enum CodingKeys: String, CodingKey {\n        case sheetID\n    }"),
                   "private coding declares only the stable UUID key")
        try expect(item.contains("container.encode(sheetID, forKey: .sheetID)"),
                   "private encoding writes the UUID")
        try expect(item.contains("exportSnapshot = nil"),
                   "decoded internal values cannot export a file")
        try expect(item.contains("exportFilename = nil"),
                   "decoded internal values carry no suggested export name")
    },
    EngineCase("sheet-drag-file-staging-is-lazy-unique-and-atomic") {
        guard let source = sheetExportAppSource("Sources/NumlexApp/Views/SidebarView.swift"),
              let itemStart = source.range(of: "struct SheetDragItem:"),
              let itemEnd = source.range(of: "extension UTType", range: itemStart.upperBound..<source.endIndex)
        else {
            throw CaseFailure(message: "SheetDragItem source block missing")
        }
        let item = String(source[itemStart.lowerBound..<itemEnd.lowerBound])
        try expect(item.contains("SentTransferredFile(try item.stageExportFile())"),
                   "staging begins lazily inside the file representation")
        try expect(item.contains(".suggestedFileName { $0.exportSuggestedName }"),
                   "the file representation declares the extensionless suggested name")
        try expect(item.contains("guard let exportSnapshot, let exportFilename else"),
                   "staging requires both the snapshot and its suggested name")
        try expect(item.contains("fileManager.temporaryDirectory"),
                   "staging stays in the system temporary directory")
        try expect(item.contains(".appendingPathComponent(UUID().uuidString, isDirectory: true)"),
                   "every drag file receives a unique staging directory")
        try expect(item.contains("appendingPathComponent(exportFilename,"),
                   "the staged file carries the centralized safe filename")
        try expect(item.contains("JSONEncoder().encode(exportSnapshot)"),
                   "staged bytes encode the captured snapshot")
        try expect(item.contains("data.write(to: fileURL, options: .atomic)"),
                   "the staged file is written atomically")
        try expect(item.contains("try? fileManager.removeItem(at: stagingDirectory)"),
                   "partial staging is removed on failure")
    },
    EngineCase("sheet-drag-external-path-is-nondestructive-and-folder-drop-unchanged") {
        guard let source = sheetExportAppSource("Sources/NumlexApp/Views/SidebarView.swift"),
              let itemStart = source.range(of: "struct SheetDragItem:"),
              let itemEnd = source.range(of: "extension UTType", range: itemStart.upperBound..<source.endIndex)
        else {
            throw CaseFailure(message: "SheetDragItem source block missing")
        }
        let item = String(source[itemStart.lowerBound..<itemEnd.lowerBound])
        for forbidden in ["model.", "selectedSheet", "moveSheet(", "deleteSheet(",
                          "select(index:", "persist("] {
            try expect(!item.contains(forbidden),
                       "file transfer has no model mutation callback: \(forbidden)")
        }
        try expect(source.contains(".dropDestination(for: SheetDragItem.self) { items, _ in"),
                   "folder tabs still accept SheetDragItem")
        try expect(source.contains("model.moveSheet(id: item.sheetID, to: groupID)"),
                   "folder drops still move by the stable UUID")
    }
]
