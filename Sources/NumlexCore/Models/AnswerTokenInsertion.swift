import Foundation

/// r43: the pure, reference-aware plan for minting ONE answer token at
/// the editor's CURRENT caret/selection — exactly like a normal typed
/// insertion at the caret. A collapsed range inserts the single U+FFFC
/// marker at its location; a non-empty selection is REPLACED by that
/// one marker; no newline and no trailing blank line are ever added.
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
