import Foundation
import NumlexCore

/// r44: repeated use of the SAME answer/source line. The model never
/// prohibited duplicate sourceLineIDs — each minted reference gets a
/// fresh UUID/location and sanitize keeps every distinct marker — so
/// rapid successive insertions from one clicked source must each land:
/// exactly one marker per pair, distinct refs, same stable source ID,
/// caret advancing one unit per token. The click-side half of the bug
/// (AppKit delivering a stationary run as 1,2,3,4...) is pinned by
/// the pure AnswerDoubleClick pair table.

private let r44M = "\u{FFFC}"
private func r44Ids(_ n: Int) -> [UUID] { (0..<n).map { _ in UUID() } }

public let r44Cases: [EngineCase] = [
    EngineCase("r44-sequential-same-source-tokens") {
        // "12" (source, line 1) with the caret at the END of line 3
        // ("2 * x", loc 14). First mint at the caret, second mint at
        // the FIRST plan's caret on the FIRST plan's output — exactly
        // what two rapid double-click pairs on one answer row do.
        let content = "12\nx = 4\n2 * x"
        let lineIDs = r44Ids(3)

        guard let p1 = AnswerTokenInsertion.plan(
            content: content, lineIDs: lineIDs, references: [],
            sourceLineIndex: 0,
            selection: NSRange(location: 14, length: 0)) else {
            throw CaseFailure(message: "first plan expected")
        }
        guard let p2 = AnswerTokenInsertion.plan(
            content: p1.content, lineIDs: p1.lineIDs,
            references: p1.references,
            sourceLineIndex: 0,
            selection: NSRange(location: p1.caret, length: 0)) else {
            throw CaseFailure(message: "second plan at first.caret expected")
        }

        // Exactly TWO markers, at the two exact consecutive positions.
        try expectEqual(p2.content, "12\nx = 4\n2 * x" + r44M + r44M,
                        "both markers land at the caret, adjacent")
        let markers = p2.content.unicodeScalars.filter { $0.value == 0xFFFC }.count
        try expectEqual(markers, 2, "exactly two U+FFFC markers")
        // No newline was ever added (3 lines before, 3 lines after).
        try expectEqual(p2.content.split(separator: "\n", omittingEmptySubsequences: false).count,
                        3, "no newline/trailing blank line added")

        // Two references: distinct IDs, exact/unique locations, BOTH
        // pointing at the original clicked source's stable line ID
        // with the same 1-based label.
        try expectEqual(p2.references.count, 2, "two references after two mints")
        let ids = Set(p2.references.map(\.id))
        try expectEqual(ids.count, 2, "reference UUIDs are distinct")
        let locs = p2.references.map(\.location).sorted()
        try expectEqual(locs, [14, 15], "locations exact and unique")
        for r in p2.references {
            try expectEqual(r.sourceLineID, lineIDs[0],
                            "duplicate source = the clicked line's STABLE id")
            try expectEqual(r.labelLine, 1, "label is the clicked line's number")
        }
        // The first mint's own reference survived the second mint.
        try expect(p2.references.contains { $0.id == p1.newReference.id },
                   "first mint's reference preserved")

        // Caret advances one unit per token; line IDs untouched.
        try expectEqual(p1.caret, 15, "first caret = marker + 1")
        try expectEqual(p2.caret, 16, "second caret = first.caret + 1")
        try expectEqual(p1.lineIDs, lineIDs, "line IDs untouched (plan 1)")
        try expectEqual(p2.lineIDs, lineIDs, "line IDs untouched (plan 2)")

        // Both tokens RESOLVE: two TokenResolutions, both active, both
        // showing the source's current value (12).
        let resolved = resolveSheet(
            content: p2.content, lineIDs: p2.lineIDs, references: p2.references,
            rates: Rates(), decimalPlaces: 2)
        try expectEqual(resolved.tokens.count, 2, "two tokens render")
        var active: [Double] = []
        for t in resolved.tokens {
            if case .active(let v, _, _) = t.state { active.append(v) }
        }
        try expectEqual(active.sorted(), [12.0, 12.0],
                        "BOTH tokens resolve active to the source's value")
    },

    EngineCase("r44-click-count-pair-table") {
        // The invariant behind the fixed mouse handler: a stationary
        // multi-click run counts 1,2,3,4,5,6 — positive EVEN counts
        // complete a double-click pair (one token each), odd counts
        // are pair starts, and 0/negative is inert.
        let table: [(Int, Bool)] = [
            (0, false), (1, false), (2, true), (3, false),
            (4, true), (5, false), (6, true),
        ]
        for (count, expected) in table {
            try expect(AnswerDoubleClick.completesPair(at: count) == expected,
                       "count \(count): expected \(expected)")
        }
    },
]
