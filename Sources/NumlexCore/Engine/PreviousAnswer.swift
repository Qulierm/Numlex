import Foundation

/// Pure eligibility planning for the "insert previous answer" input
/// helper (r19). Given the current sheet content, the caret position and
/// the operator the user is typing on a NEW line, finds the nearest
/// earlier answerable line. No UI, no mutation: the model applies the
/// plan atomically.
public enum PreviousAnswerPlan {

    /// Operators accepted on the new line (what a user can type).
    public static let operators: Set<Character> = ["+", "-", "*", "/", "×", "÷", "−"]

    public struct Plan: Equatable, Sendable {
        /// 0-based logical index of the source line.
        public let sourceLineIndex: Int
        /// The source line's STABLE identity (into `Sheet.lineIDs`).
        public let sourceLineID: UUID
        /// UTF-16 insertion point (the caret) in the current content.
        public let insertionLocation: Int
        /// The operator the user typed, verbatim.
        public let operatorCharacter: Character
    }

    /// Scans DOWN from the caret's line. Eligible: a line whose CURRENT
    /// resolution is a finite number (with or without unit — conversion
    /// results are numbers and qualify), a variable, or a finite money
    /// answer. A token-derived expression qualifies whenever the token
    /// resolves active (with the given live `references`); a BROKEN
    /// token, date, title, blank, prose, error or non-finite line never
    /// qualifies. The caret's line must be blank (whitespace only).
    ///
    /// `references` is the sheet's CURRENT sidecar: without it every
    /// token line resolves broken and token chains can never be the
    /// source line. Defaults to `[]` for callers that only deal in
    /// token-free content (tests, paste paths).
    public static func plan(
        content: String,
        lineIDs: [UUID],
        caret: Int,
        op: Character,
        rates: Rates = Rates(),
        decimalPlaces: Int = 7,
        references: [AnswerReference] = []
    ) -> Plan? {
        guard operators.contains(op) else { return nil }
        let ns = content as NSString
        guard caret >= 0, caret <= ns.length else { return nil }
        let lines = content.components(separatedBy: "\n")
        let caretLine = ns.substring(to: caret).components(separatedBy: "\n").count - 1
        guard lines.indices.contains(caretLine) else { return nil }
        guard lines[caretLine].allSatisfy({ $0 == " " || $0 == "\t" }) else { return nil }
        let resolved = resolveSheet(
            content: content, lineIDs: lineIDs, references: references,
            rates: rates, decimalPlaces: decimalPlaces
        )
        for i in stride(from: caretLine - 1, through: 0, by: -1) {
            guard resolved.lines.indices.contains(i) else { continue }
            guard isAnswerable(resolved.lines[i].result) else { continue }
            let id = lineIDs.indices.contains(i) ? lineIDs[i] : UUID()
            return Plan(sourceLineIndex: i, sourceLineID: id,
                        insertionLocation: caret, operatorCharacter: op)
        }
        return nil
    }

    /// The answerable shapes: a finite number (with or without unit —
    /// conversions resolve to numbers and qualify), a variable, or a
    /// finite money answer.
    public static func isAnswerable(_ result: LineResult) -> Bool {
        switch result {
        case .number(let v, _): return v.isFinite
        case .variable: return true
        case .money(let v, _): return v.isFinite
        case .blank, .skip, .title, .date, .brokenToken, .error: return false
        }
    }

    /// Applies a plan to the sheet payload (r19). The edit is a PURE
    /// MID-DOCUMENT INSERTION of `marker + separator + operator` at
    /// `plan.insertionLocation` — no newline — so every pre-existing
    /// reference located at or after the insertion moves by the
    /// insertion's UTF-16 length, references before it stay put, and
    /// the line-ID table is untouched. The fresh reference (pointing
    /// at `plan.sourceLineID`) is appended and the whole set is
    /// sanitized, so a corrupt input can never ship dead markers and
    /// the new marker can never be orphaned. Returns the caret
    /// position, right after the inserted text.
    public static func apply(
        plan: Plan,
        content: String,
        lineIDs: [UUID],
        references: [AnswerReference],
        operatorText: String,
        separator: String
    ) -> (content: String, lineIDs: [UUID], references: [AnswerReference], caret: Int) {
        let insertion = String(answerTokenMarker) + separator + operatorText
        let newContent = (content as NSString).replacingCharacters(
            in: NSRange(location: plan.insertionLocation, length: 0),
            with: insertion)
        let shift = (insertion as NSString).length
        var refs = references.map { r in
            r.location >= plan.insertionLocation
                ? r.withLocation(r.location + shift)
                : r
        }
        refs.append(AnswerReference(
            sourceLineID: plan.sourceLineID,
            labelLine: plan.sourceLineIndex + 1,
            location: plan.insertionLocation
        ))
        return (newContent, lineIDs,
                Sheet.sanitizeReferences(refs, in: newContent),
                plan.insertionLocation + shift)
    }
}
