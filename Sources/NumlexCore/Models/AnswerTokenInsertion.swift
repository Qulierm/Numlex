import Foundation

/// r43: the pure, reference-aware plan for minting ONE answer token at
/// the editor's CURRENT caret/selection. A caret (or a contained
/// selection) on a line OTHER than the clicked source line inserts the
/// single U+FFFC marker at the caret — a non-empty selection is
/// REPLACED by that one marker. A caret or contained selection on the
/// SOURCE line itself (r80) would mint a circular self-reference, so
/// the marker goes to a NEW logical line immediately after the entire
/// source line instead; the source line and every following line are
/// preserved verbatim (see `planSameLine`).
///
/// The source identity comes from the CLICKED source line (stable line
/// ID + 1-based label), independent of the line the caret happens to
/// sit on. All marker/line bookkeeping goes through the same
/// `LineIdentity.reconcile` pipeline as user typing, so existing
/// references are preserved, shifted, or dropped exactly as a normal
/// edit would do. Invalid or stale requests (bad source index,
/// out-of-bounds or overflowing ranges, surrogate/grapheme-splitting
/// boundaries) yield `nil` — a deterministic no-op at the call site
/// (nothing is persisted, retitled, focused, or animated).
public enum AnswerTokenInsertion {

    /// The fully-applied result of one caret insertion: final content,
    /// final line IDs, final references (fresh token included and
    /// sanitized), the UTF-16 caret that lands right after the marker,
    /// and the fresh reference itself.
    public struct Plan: Equatable, Sendable {
        public let content: String
        public let lineIDs: [UUID]
        public let references: [AnswerReference]
        public let caret: Int
        public let newReference: AnswerReference

        public init(content: String,
                    lineIDs: [UUID],
                    references: [AnswerReference],
                    caret: Int,
                    newReference: AnswerReference) {
            self.content = content
            self.lineIDs = lineIDs
            self.references = references
            self.caret = caret
            self.newReference = newReference
        }
    }

    /// True when `utf16Offset` lands exactly on a Character (extended
    /// grapheme cluster) boundary of `s` — walking the Characters and
    /// accumulating their UTF-16 lengths, so surrogate pairs, combining
    /// sequences and emoji/ZWJ sequences are all treated as atomic.
    private static func isCharacterBoundary(_ utf16Offset: Int, in s: String) -> Bool {
        guard utf16Offset >= 0 else { return false }
        let total = (s as NSString).length
        guard utf16Offset <= total else { return false }
        var acc = 0
        for ch in s {
            if acc == utf16Offset { return true }
            acc += (String(ch) as NSString).length
            if acc > utf16Offset { return false }
        }
        return acc == utf16Offset
    }

    /// Builds the plan, or `nil` when the request is invalid.
    ///
    /// - Parameters:
    ///   - content: the pre-edit sheet content.
    ///   - lineIDs: the pre-edit logical line IDs (1:1 with lines).
    ///   - references: the pre-edit reference sidecar.
    ///   - sourceLineIndex: the index of the line the clicked answer
    ///     belongs to (its stable ID becomes the token's source).
    ///   - selection: the live editor selection in UTF-16 units. A
    ///     length-0 range inserts at the caret; a longer range is
    ///     replaced by the single marker.
    public static func plan(
        content: String,
        lineIDs: [UUID],
        references: [AnswerReference],
        sourceLineIndex: Int,
        selection: NSRange
    ) -> Plan? {
        // --- source identity (captured from the PRE-EDIT sheet) ---
        guard lineIDs.indices.contains(sourceLineIndex) else { return nil }
        let sourceLineID = lineIDs[sourceLineIndex]
        let labelLine = sourceLineIndex + 1

        // The pre-edit line starts (UTF-16), walked once and reused by
        // both the same-line detection below and the same-line branch.
        let ns2 = content as NSString
        var lineStarts: [Int] = [0]
        var pos = 0
        while pos <= ns2.length {
            let r = ns2.range(of: "\n", options: [],
                              range: NSRange(location: pos, length: ns2.length - pos))
            if r.location == NSNotFound { break }
            let next = r.location + 1
            guard next <= ns2.length else { break }
            lineStarts.append(next)
            pos = next
        }
        let ls = lineStarts[sourceLineIndex]
        // The last line's "end" is one PAST the content end: a caret at
        // the document end sits on the last line, not past it.
        let le = sourceLineIndex + 1 < lineStarts.count
            ? lineStarts[sourceLineIndex + 1]
            : ns2.length + 1

        // --- rigorous UTF-16 range validation ---
        let ns = content as NSString
        guard selection.location >= 0, selection.length >= 0 else { return nil }
        // Overflow-safe bounds: the range must fit inside the pre-edit
        // content (no wrapping arithmetic, no negative remainders).
        guard selection.location <= ns.length else { return nil }
        guard selection.length <= ns.length - selection.location else { return nil }
        let end = selection.location + selection.length
        // Composed-boundary validation: BOTH ends must align to Swift
        // Character (extended grapheme cluster) boundaries. A range
        // that splits a surrogate pair or a combining-mark sequence
        // (e + U+0301, emoji ZWJ sequences, …) is malformed — a
        // deterministic no-op, never a corruption. (`Range(NSRange:)`
        // alone would only catch surrogate splits, so the boundary set
        // is derived by walking the Characters explicitly.)
        guard isCharacterBoundary(selection.location, in: content),
              isCharacterBoundary(end, in: content) else { return nil }
        // The insertion is a SINGLE-LINE edit: a selection that crosses a
        // newline would MERGE two logical lines into one — a destructive
        // restructure for a double-click. Deterministic no-op (the user
        // can still type normally; only the token minting is refused).
        guard ns.substring(with: selection).range(of: "\n") == nil,
              ns.substring(with: selection).range(of: "\r") == nil else { return nil }
        // A zero-length caret counts as "on" the line from its start
        // through the last unit before the next line's start; a
        // non-empty selection overlaps it when it is strictly inside
        // (newline-carrying selections were refused above).
        let selOverlapsSource = selection.length == 0
            ? (selection.location >= ls && selection.location < le)
            : (selection.location < le && end > ls)
        if selOverlapsSource {
            // r80: the user asked for a bubble while the caret sits on
            // the clicked line — mint it on a NEW line right after the
            // source instead of refusing (a marker placed on the source
            // line would be circular and break that line's result).
            return planSameLine(
                ns: ns2,
                lineStarts: lineStarts,
                le: le,
                lineIDs: lineIDs,
                references: references,
                sourceLineID: sourceLineID,
                labelLine: labelLine,
                sourceLineIndex: sourceLineIndex
            )
        }

        // --- apply exactly like typing: replace, never append ---
        let marker = String(answerTokenMarker)
        let newContent = ns.replacingCharacters(in: selection, with: marker)

        // --- one NotebookEdit through the shared reconciliation so
        //     existing marker locations and line IDs behave EXACTLY as
        //     normal editing (before: stable, inside: dropped, after:
        //     shifted by the replacement's length). ---
        let edit = NotebookEdit(range: selection, replacement: marker)
        let (newLineIDs, keptReferences) = LineIdentity.reconcile(
            oldContent: content,
            oldLineIDs: lineIDs,
            oldReferences: references,
            newContent: newContent,
            edit: edit
        )

        // --- the fresh reference: replacement start, stable source ---
        let newReference = AnswerReference(
            sourceLineID: sourceLineID,
            labelLine: labelLine,
            location: selection.location
        )
        // A PRE-EXISTING token fully covered by the replaced selection
        // survives reconciliation at the same spot (the replacement
        // re-introduces a marker at the replacement's start). A single
        // marker can carry exactly ONE reference, and the freshly minted
        // token takes the slot: drop the displaced reference, keep the
        // fresh one. No other position can collide (one marker per
        // location before the edit, and only in-range markers move to
        // the replacement's start).
        var finalReferences = Sheet.sanitizeReferences(
            keptReferences + [newReference], in: newContent)
        finalReferences.removeAll { ref in
            ref.id != newReference.id && ref.location == newReference.location
        }
        // Defense in depth: the marker is placed verbatim, so this can
        // only fail if reconciliation misbehaved — in that case the
        // whole insertion is a no-op rather than a corrupted sheet.
        guard finalReferences.contains(where: { $0.id == newReference.id }) else { return nil }

        return Plan(
            content: newContent,
            lineIDs: newLineIDs,
            references: finalReferences,
            caret: selection.location + 1, // the marker is exactly one UTF-16 unit
            newReference: newReference
        )
    }

    /// r80: the SAME-LINE branch. The caret (or a contained non-empty
    /// selection) sits on the clicked source line; the marker goes to a
    /// NEW logical line immediately after the entire source line,
    /// holding exactly one U+FFFC token referencing the source's stable
    /// ID, with the caret landing right after the marker.
    ///
    /// Newline contract — the source expression and every following
    /// line are preserved VERBATIM; exactly one newline is inserted,
    /// never a join, delete or re-wrap:
    ///
    ///   "7×8"       -> "7×8\n<marker>"      (last line without a
    ///                                                     newline: one \n at
    ///                                                     the document end)
    ///   "7×8\nB"    -> "7×8\n<marker>\nB"   (marker + \n after the
    ///                                                     source's own newline)
    ///   "7×8\n\nB"  -> "7×8\n<marker>\n\nB" (an existing BLANK next
    ///                                                     line is preserved
    ///                                                     after the new line)
    ///
    /// The inserted text is applied as ONE pure NotebookEdit (zero
    /// length) through the shared `LineIdentity.reconcile` pipeline, so
    /// the source line ID is preserved exactly, the fresh line is
    /// minted a new stable ID, and every following line's UTF-16 ranges
    /// and references shift by the inserted length; rounding overrides
    /// are untouched (they key off line IDs). The caret lands after the
    /// marker, on the new line — a second double-click pair on the same
    /// answer now inserts at that caret (a line different from the
    /// source) and mints the next bubble there, adding no further
    /// lines.
    private static func planSameLine(
        ns: NSString,
        lineStarts: [Int],
        le: Int,
        lineIDs: [UUID],
        references: [AnswerReference],
        sourceLineID: UUID,
        labelLine: Int,
        sourceLineIndex: Int
    ) -> Plan? {
        let marker = String(answerTokenMarker)
        // Where the marker line goes: after the source line's own
        // newline (marker first — the next line, blank or not, keeps
        // its own start), or at the document end with one leading
        // newline when the source line is the last line and owns none.
        let hasOwnNewline = sourceLineIndex + 1 < lineStarts.count
        let insertPos: Int
        let text: String
        let markerOffset: Int
        if hasOwnNewline {
            // `le` is the next line's start (just past the source's
            // newline); inserting here keeps both lines intact.
            insertPos = le
            text = marker + "\n"
            markerOffset = 0
        } else {
            insertPos = ns.length
            text = "\n" + marker
            markerOffset = 1
        }

        let newContent = ns.replacingCharacters(
            in: NSRange(location: insertPos, length: 0), with: text)
        // One NotebookEdit through the shared reconciliation — the
        // source line keeps its ID, the new line is minted, the lines
        // after shift by the inserted length, and existing references
        // shift or survive exactly like a typed insertion would.
        let edit = NotebookEdit(range: NSRange(location: insertPos, length: 0),
                                replacement: text)
        let (newLineIDs, keptReferences) = LineIdentity.reconcile(
            oldContent: String(ns),
            oldLineIDs: lineIDs,
            oldReferences: references,
            newContent: newContent,
            edit: edit
        )

        let newReference = AnswerReference(
            sourceLineID: sourceLineID,
            labelLine: labelLine,
            location: insertPos + markerOffset
        )
        // The fresh marker sits at a position no old marker could
        // occupy (a brand-new line / document end), so the usual
        // same-location displacement sweep is a no-op kept for parity.
        var finalReferences = Sheet.sanitizeReferences(
            keptReferences + [newReference], in: newContent)
        finalReferences.removeAll { ref in
            ref.id != newReference.id && ref.location == newReference.location
        }
        // Defense in depth: the marker is placed verbatim, so this can
        // only fail if reconciliation misbehaved — in that case the
        // whole insertion is a no-op rather than a corrupted sheet.
        guard finalReferences.contains(where: { $0.id == newReference.id }) else { return nil }

        return Plan(
            content: newContent,
            lineIDs: newLineIDs,
            references: finalReferences,
            caret: newReference.location + 1, // right after the one marker
            newReference: newReference
        )
    }
}

/// r44: click-count semantics for the answer surface's double-tap.
///
/// A rapid stationary multi-click run is delivered by AppKit as a
/// SINGLE mouse-down sequence with clickCounts 1, 2, 3, 4, 5, ...:
/// every POSITIVE EVEN count (2, 4, 6, ...) completes exactly one
/// double-click PAIR and must mint exactly one token; odd counts
/// (1, 3, 5, ...) are pair STARTS and must never fire. Firing only on
/// `clickCount == 2` (the r43 behavior) makes the second, third, ...
/// pair of an unbroken run silently inert, so one answer row appeared
/// usable only once during the run.
public enum AnswerDoubleClick {
    /// True exactly when this clickCount completes a double-click pair.
    public static func completesPair(at clickCount: Int) -> Bool {
        clickCount > 0 && clickCount.isMultiple(of: 2)
    }
}
