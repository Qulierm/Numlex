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

    /// Scans DOWN from the caret's line. Eligible: a finite number
    /// (with or without unit), a variable, or a finite money answer.
    /// Conversion/date/error/title/prose/token lines never qualify.
    /// The caret's line must be blank (whitespace only).
    public static func plan(
        content: String,
        lineIDs: [UUID],
        caret: Int,
        op: Character,
        rates: Rates = Rates(),
        decimalPlaces: Int = 7
    ) -> Plan? {
        guard operators.contains(op) else { return nil }
        let ns = content as NSString
        guard caret >= 0, caret <= ns.length else { return nil }
        let lines = content.components(separatedBy: "\n")
        let caretLine = ns.substring(to: caret).components(separatedBy: "\n").count - 1
        guard lines.indices.contains(caretLine) else { return nil }
        guard lines[caretLine].allSatisfy({ $0 == " " || $0 == "\t" }) else { return nil }
        let resolved = resolveSheet(
            content: content, lineIDs: lineIDs, references: [],
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

    /// The answerable shapes: a finite number (with or without unit),
    /// a variable, or a finite money answer.
    public static func isAnswerable(_ result: LineResult) -> Bool {
        switch result {
        case .number(let v, _): return v.isFinite
        case .variable: return true
        case .money(let v, _): return v.isFinite
        case .blank, .skip, .title, .date, .brokenToken, .error: return false
        }
    }
}
