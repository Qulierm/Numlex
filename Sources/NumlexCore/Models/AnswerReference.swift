import Foundation

/// The single U+FFFC object-replacement marker every answer token
/// occupies in `Sheet.content`. Exactly ONE UTF-16 unit: TextKit renders
/// it as a capsule attachment, the evaluator resolves it to the current
/// value of its source line, and one Backspace deletes it atomically.
public let answerTokenMarkerUTF16: UInt16 = 0xFFFC
public let answerTokenMarker: Character = "\u{FFFC}"

/// A live answer reference token: one U+FFFC marker in a sheet's content
/// plus sidecar metadata. The token ALWAYS displays the current value of
/// its source line (resolved at evaluation time) — no numeric snapshot is
/// ever stored as truth. If the source line is deleted or stops
/// evaluating to a number/variable, the token stays in place but becomes
/// inactive and displays its remembered `Line N` label.
public struct AnswerReference: Codable, Equatable, Identifiable, Sendable {
    /// The token's own identity (stable across content edits).
    public var id: UUID
    /// The stable ID of the source logical line (into `Sheet.lineIDs`),
    /// never an index — edits above must not redirect the reference.
    public var sourceLineID: UUID
    /// The 1-based line number of the source at insertion time; an
    /// inactive token displays `Line <labelLine>`.
    public var labelLine: Int
    /// UTF-16 offset of the U+FFFC marker inside `Sheet.content`.
    public var location: Int

    public init(id: UUID = UUID(), sourceLineID: UUID, labelLine: Int, location: Int) {
        self.id = id
        self.sourceLineID = sourceLineID
        self.labelLine = labelLine
        self.location = location
    }
}

/// One user edit as AppKit announces it BEFORE performing it: the range
/// replaced in the pre-edit content and the replacement string
/// (`""` for a pure deletion). The line-identity reconciliation uses it
/// to update marker positions exactly; when nil (unknown), a content-
/// based alignment fallback is used instead.
public struct NotebookEdit: Equatable, Sendable {
    public let range: NSRange?
    public let replacement: String
    /// The EXACT UTF-16 caret map of the format pass applied after the
    /// announced edit (from the post-edit text to the stored text).
    /// Nil = unknown: reconciliation infers the legacy canonical map.
    public let formatMap: [Int]?
    public init(range: NSRange? = nil, replacement: String = "", formatMap: [Int]? = nil) {
        self.range = range
        self.replacement = replacement
        self.formatMap = formatMap
    }
}

/// Pure line-identity reconciliation: maps a sheet's logical line IDs and
/// token marker locations from one content state to the next, following
/// the ACTUAL user edit (range + replacement) where known. The canonical
/// format pass that may follow the edit is replayed with
/// `NotebookFormatting.mapDocument`, so marker positions stay exact even
/// when the formatter re-spaces a line. Never throws, never fabricates:
/// a marker that cannot be proven to survive is dropped.
public enum LineIdentity {

    public static func reconcile(
        oldContent: String,
        oldLineIDs: [UUID],
        oldReferences: [AnswerReference],
        newContent: String,
        edit: NotebookEdit?
    ) -> (lineIDs: [UUID], references: [AnswerReference]) {
        let oldLines = oldContent.components(separatedBy: "\n")
        let newLines = newContent.components(separatedBy: "\n")
        let base: [UUID] = oldLineIDs.count == oldLines.count
            ? oldLineIDs
            : oldLines.map { _ in UUID() }

        let (newToOld, oldToNew) = alignLines(oldLines, newLines)

        var lineIDs = [UUID]()
        lineIDs.reserveCapacity(newLines.count)
        for i in 0..<newLines.count {
            if let oldIdx = newToOld[i] {
                lineIDs.append(base[oldIdx])
            } else {
                lineIDs.append(UUID())
            }
        }

        let references = remapReferences(
            oldReferences: oldReferences,
            oldContent: oldContent,
            newContent: newContent,
            oldToNew: oldToNew,
            edit: edit
        )
        return (lineIDs, references)
    }

    // MARK: - Line alignment

    /// Maps logical line indices between two contents. Stable ends are
    /// anchored by longest common prefix/suffix; the small middle region
    /// is aligned with deterministic edit-shape rules:
    /// - equal counts: 1:1 in place (ordinary edits);
    /// - a line split by a typed newline: the FIRST part keeps the ID;
    /// - a Backspace merge at a line start: the PREVIOUS line's ID
    ///   survives on the merged line;
    /// - an in-place truncation (including to empty): the ID survives;
    /// - pasted/inserted lines: fresh IDs.
    private static func alignLines(_ oldLines: [String], _ newLines: [String]) -> (newToOld: [Int: Int], oldToNew: [Int: Int]) {
        var prefix = 0
        let maxPrefix = min(oldLines.count, newLines.count)
        while prefix < maxPrefix, oldLines[prefix] == newLines[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < oldLines.count - prefix, suffix < newLines.count - prefix,
              oldLines[oldLines.count - 1 - suffix] == newLines[newLines.count - 1 - suffix] {
            suffix += 1
        }
        var newToOld: [Int: Int] = [:]
        var oldToNew: [Int: Int] = [:]
        for i in 0..<prefix { newToOld[i] = i; oldToNew[i] = i }
        for i in 0..<suffix {
            let n = newLines.count - 1 - i
            let o = oldLines.count - 1 - i
            newToOld[n] = o
            oldToNew[o] = n
        }
        let oldMid = Array(prefix..<(oldLines.count - suffix))
        let newMid = Array(prefix..<(newLines.count - suffix))
        if oldMid.count == newMid.count {
            for k in 0..<oldMid.count {
                newToOld[newMid[k]] = oldMid[k]
                oldToNew[oldMid[k]] = newMid[k]
            }
        } else {
            var oi = 0
            for ni in newMid {
                let nline = newLines[ni]
                if oi < oldMid.count, oldLines[oldMid[oi]] == nline {
                    newToOld[ni] = oldMid[oi]; oldToNew[oldMid[oi]] = ni; oi += 1
                } else if oi + 1 < oldMid.count,
                          oldLines[oldMid[oi]] + oldLines[oldMid[oi + 1]] == nline {
                    // Backspace merge at the next line's start keeps the
                    // PREVIOUS line's ID.
                    newToOld[ni] = oldMid[oi]; oldToNew[oldMid[oi]] = ni; oi += 2
                } else if oi < oldMid.count, !oldLines[oldMid[oi]].isEmpty,
                          nline.hasPrefix(oldLines[oldMid[oi]]) {
                    // A newline split inside the old line: the first part
                    // keeps the ID, the rest are new lines.
                    newToOld[ni] = oldMid[oi]; oldToNew[oldMid[oi]] = ni; oi += 1
                } else if oi < oldMid.count, !nline.isEmpty,
                          (oldLines[oldMid[oi]] as NSString).hasPrefix(nline) {
                    // In-place truncation keeps the ID.
                    newToOld[ni] = oldMid[oi]; oldToNew[oldMid[oi]] = ni; oi += 1
                } else if oi < oldMid.count, nline.isEmpty, !oldLines[oldMid[oi]].isEmpty {
                    // A Backspace truncated the line to empty: the line
                    // (and its ID) survives.
                    newToOld[ni] = oldMid[oi]; oldToNew[oldMid[oi]] = ni; oi += 1
                } else {
                    // A purely new line (paste or inserted blank): fresh ID.
                }
            }
        }
        return (newToOld, oldToNew)
    }

    // MARK: - Marker remapping

    /// Updates every reference's marker location for the transition from
    /// `oldContent` to `newContent`. With a known edit the marker is moved
    /// by the edit itself and then through the format map; without one
    /// (or when the edit cannot be replayed) the marker is re-derived from
    /// its line's aligned successor (k-th marker in the old line becomes
    /// the k-th marker in the new line). A marker that ends up pointing at
    /// anything other than U+FFFC is dropped.
    private static func remapReferences(
        oldReferences: [AnswerReference],
        oldContent: String,
        newContent: String,
        oldToNew: [Int: Int],
        edit: NotebookEdit?
    ) -> [AnswerReference] {
        let fns = newContent as NSString
        var refs: [AnswerReference] = []
        if let edit, let range = edit.range,
           range.location >= 0, range.length >= 0,
           range.location + range.length <= (oldContent as NSString).length {
            let intermediate = (oldContent as NSString)
                .replacingCharacters(in: range, with: edit.replacement)
            for ref in oldReferences {
                let p = ref.location
                guard p >= 0, p <= (oldContent as NSString).length else { continue }
                var inter: Int
                if p < range.location {
                    inter = p
                } else if p >= range.location + range.length {
                    inter = p - range.length + (edit.replacement as NSString).length
                } else {
                    // The marker was inside the replaced range. If the
                    // replacement re-introduces a marker (selection
                    // replaced by text containing the same token), the
                    // token survives at the replacement's marker offset;
                    // otherwise it was deleted with the selection.
                    let repNS = edit.replacement as NSString
                    let repRange = repNS.range(of: String(answerTokenMarker))
                    if repRange.location == NSNotFound { continue }
                    inter = range.location + repRange.location
                }
                let finalPos: Int
                if intermediate == newContent {
                    finalPos = inter
                } else if let formatMap = edit.formatMap,
                          formatMap.count == (intermediate as NSString).length + 1 {
                    // The editor's actual preference-aware pass: exact.
                    finalPos = formatMap[min(max(inter, 0), formatMap.count - 1)]
                } else if NotebookFormatting.canonicalDocument(intermediate) == newContent {
                    let map = NotebookFormatting.mapDocument(from: intermediate, to: newContent)
                    finalPos = map[min(max(inter, 0), map.count - 1)]
                } else if let pos = remapByLine(ref: ref, oldContent: oldContent, newContent: newContent, oldToNew: oldToNew) {
                    refs.append(ref.withLocation(pos))
                    continue
                } else {
                    continue
                }
                if finalPos >= 0, finalPos < fns.length,
                   fns.character(at: finalPos) == answerTokenMarkerUTF16 {
                    refs.append(ref.withLocation(finalPos))
                }
            }
        } else {
            for ref in oldReferences {
                if let pos = remapByLine(ref: ref, oldContent: oldContent, newContent: newContent, oldToNew: oldToNew) {
                    refs.append(ref.withLocation(pos))
                }
            }
        }
        return refs.sorted { $0.location < $1.location }
    }

    /// Content-based fallback: the marker's old line is mapped to its
    /// aligned successor and the k-th marker in the old line becomes the
    /// k-th marker in the new line.
    private static func remapByLine(
        ref: AnswerReference,
        oldContent: String,
        newContent: String,
        oldToNew: [Int: Int]
    ) -> Int? {
        let ons = oldContent as NSString
        guard ref.location >= 0, ref.location <= ons.length else { return nil }
        let oldLines = oldContent.components(separatedBy: "\n")
        let newLines = newContent.components(separatedBy: "\n")
        let lineIdx = ons.substring(to: ref.location).components(separatedBy: "\n").count - 1
        guard oldLines.indices.contains(lineIdx) else { return nil }
        guard let newLineIdx = oldToNew[lineIdx] else { return nil } // line deleted
        guard newLines.indices.contains(newLineIdx) else { return nil }
        let oline = oldLines[lineIdx]
        let oldStart = (oldLines.prefix(lineIdx).map { ($0 as NSString).length + 1 }).reduce(0, +)
        let withinOld = ref.location - oldStart
        guard withinOld >= 0, withinOld <= (oline as NSString).length else { return nil }
        // The k-th marker of the old line (0-based).
        let before = String((oline as NSString).substring(to: withinOld))
        let k = before.components(separatedBy: String(answerTokenMarker)).count - 1
        let nline = newLines[newLineIdx]
        let newStart = (newLines.prefix(newLineIdx).map { ($0 as NSString).length + 1 }).reduce(0, +)
        let nl = nline as NSString
        var count = 0
        var s = 0
        while s < nl.length {
            if nl.character(at: s) == answerTokenMarkerUTF16 {
                if count == k { return newStart + s }
                count += 1
            }
            s += 1
        }
        return nil // the marker no longer exists on the line
    }
}

extension AnswerReference {
    /// A copy of the reference pointing at a new marker location.
    public func withLocation(_ location: Int) -> AnswerReference {
        var copy = self
        copy.location = location
        return copy
    }
}
