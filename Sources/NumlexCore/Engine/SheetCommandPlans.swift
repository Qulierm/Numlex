import Foundation

/// Package 7: ONE pure edit applied to a single logical line (its range
/// is announced through `NotebookEdit` so line identity and the
/// reference sidecar reconcile exactly).
public struct SheetCommandEditPlan: Equatable, Sendable {
    public let content: String
    public let edit: NotebookEdit
    public let caret: Int
    public let lineIndex: Int

    public init(content: String, edit: NotebookEdit, caret: Int, lineIndex: Int) {
        self.content = content
        self.edit = edit
        self.caret = caret
        self.lineIndex = lineIndex
    }
}

/// Package 7: the pure insertion planner for the Add Subtotal / Add
/// Grand Total commands.
///
/// Accepted targets ONLY:
/// - a whitespace-only logical line: its whitespace is replaced by the
///   command text (`subtotal` / `grand total`);
/// - a strict valid empty assignment `<name> =` (trailing whitespace
///   allowed): the RHS is filled, yielding `<name> = subtotal` (the
///   user's named-subtotal workflow).
///
/// Anything else is nil — the caller beeps and changes nothing.
public enum SubtotalInsertionPlan {
    /// The accepted empty-answer targets (the SAME predicate `plan`
    /// enforces): a whitespace-only logical line, or a strict valid
    /// empty assignment `<name> =` with optional trailing whitespace.
    /// Pure so the double-click dispatch and its tests share it.
    public static func isEligibleTarget(line: String) -> Bool {
        if line.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        guard let split = BooleanLogic.assignmentSplit(line) else { return false }
        let lhs = split.lhs.trimmingCharacters(in: .whitespaces)
        guard SheetAggregateCommand.isValidName(lhs) else { return false }
        return split.rhs.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public static func plan(content: String,
                            lineIndex: Int,
                            command: String,
                            priorSubtotalCount: Int) -> SheetCommandEditPlan? {
        let lines = content.components(separatedBy: "\n")
        guard lines.indices.contains(lineIndex) else { return nil }
        if command.lowercased() == "grand total", priorSubtotalCount < 2 {
            return nil
        }
        let line = lines[lineIndex]
        let ns = line as NSString
        let lineStart = docOffset(lines: lines, lineIndex: lineIndex)
        if line.trimmingCharacters(in: .whitespaces).isEmpty {
            let replacement = command
            let range = NSRange(location: lineStart, length: ns.length)
            let newLines = lines
            var updated = newLines
            updated[lineIndex] = replacement
            let newContent = updated.joined(separator: "\n")
            return SheetCommandEditPlan(
                content: newContent,
                edit: NotebookEdit(range: range, replacement: replacement),
                caret: lineStart + (replacement as NSString).length,
                lineIndex: lineIndex)
        }
        // Strict valid empty assignment: `<name> =` with optional
        // trailing whitespace only.
        guard let split = BooleanLogic.assignmentSplit(line) else { return nil }
        let lhs = split.lhs.trimmingCharacters(in: .whitespaces)
        guard SheetAggregateCommand.isValidName(lhs) else { return nil }
        guard split.rhs.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let rhsStart = (split.lhs as NSString).length + 1
        let prefix = ns.substring(to: rhsStart)
        let replacementText = " " + command
        let range = NSRange(location: lineStart + rhsStart,
                            length: ns.length - rhsStart)
        var updated = lines
        updated[lineIndex] = prefix + replacementText
        let newContent = updated.joined(separator: "\n")
        return SheetCommandEditPlan(
            content: newContent,
            edit: NotebookEdit(range: range, replacement: replacementText),
            caret: lineStart + (prefix as NSString).length
                + (replacementText as NSString).length,
            lineIndex: lineIndex)
    }

    static func docOffset(lines: [String], lineIndex: Int) -> Int {
        var offset = 0
        for i in 0..<lineIndex {
            offset += (lines[i] as NSString).length + 1
        }
        return offset
    }
}

/// Package 7: the pure double-click dispatch contract shared by the
/// answer-pane click catcher and its tests. A successful answer row
/// mints a token (unless the row is dynamic); an EMPTY-answer row
/// (whitespace-only or strict `<name> =`) inserts a subtotal through
/// the same pure planner; every other quiet row (heading, comment,
/// divider, tag-only, prose, error, derived aggregate target…) is
/// inert.
public enum AnswerDoubleTapAction: Equatable, Sendable {
    /// Mint an answer token referencing the clicked row.
    case mintToken
    /// Insert `subtotal` into the empty target row.
    case insertSubtotal
    /// Do nothing (the clicked row has no double-click action).
    case inert
}

public enum AnswerDoubleTapPlan {
    /// The result kinds the double-click currently tokenizes. Exactly
    /// the pre-Package-7 set: `.number`, `.variable`, `.money`.
    public static func isTokenizable(_ result: LineResult) -> Bool {
        switch result {
        case .number, .variable, .money: return true
        default: return false
        }
    }

    /// The action for one clicked row. `sourceLine` is the ORIGINAL
    /// logical source line (the eligibility check never trusts the
    /// evaluated result kind alone). `isDynamic` is the orthogonal
    /// Package 7 taint: a dynamic row is never tokenized, even though
    /// its result is a finite number.
    public static func action(for result: LineResult,
                              sourceLine: String,
                              isDynamic: Bool) -> AnswerDoubleTapAction {
        if isDynamic { return .inert }
        if isTokenizable(result) { return .mintToken }
        if SubtotalInsertionPlan.isEligibleTarget(line: sourceLine) {
            return .insertSubtotal
        }
        return .inert
    }
}

/// Package 7: the pure Convert to Normal Line planner for a
/// subtotal/grand-total row. The command projection is replaced by a
/// locale-retypeable full-precision numeric literal; a named form keeps
/// its `<name> =` prefix. The line count (and therefore every stable
/// line ID) is unchanged.
public enum SubtotalConversionPlan {
    public static func plan(content: String,
                            lineIndex: Int,
                            value: Double,
                            context: NumberFormatContext) -> SheetCommandEditPlan? {
        let lines = content.components(separatedBy: "\n")
        guard lines.indices.contains(lineIndex) else { return nil }
        guard value.isFinite else { return nil }
        let line = lines[lineIndex]
        let analysis = SheetLineAnalysis.parse(line)
        guard analysis.kind == .expression || analysis.kind == .totalCommand else {
            return nil
        }
        // Locale-retypeable full precision: the shortest round-trip
        // decimal, with the active decimal separator and no grouping
        // (an exponent form is left as-is — the parser accepts it).
        var literal = String(value)
        if context.decimalComma {
            literal = literal.replacingOccurrences(of: ".", with: ",")
        }
        let ns = line as NSString
        let lineStart = SubtotalInsertionPlan.docOffset(lines: lines, lineIndex: lineIndex)
        var updated = lines
        var replacement: String
        var range: NSRange
        if let split = BooleanLogic.assignmentSplit(line),
           SheetAggregateCommand.isValidName(split.lhs.trimmingCharacters(in: .whitespaces)),
           (SheetAggregateCommand.subtotalRHS(split.rhs, context: context) != nil
            || SheetAggregateCommand.isGrandTotalBody(split.rhs)) {
            // Named form: keep `<name> =` and replace everything after.
            let rhsStart = (split.lhs as NSString).length + 1
            let prefix = ns.substring(to: rhsStart)
            replacement = " " + literal
            range = NSRange(location: lineStart + rhsStart,
                            length: ns.length - rhsStart)
            updated[lineIndex] = prefix + replacement
        } else {
            replacement = literal
            range = NSRange(location: lineStart, length: ns.length)
            updated[lineIndex] = replacement
        }
        return SheetCommandEditPlan(
            content: updated.joined(separator: "\n"),
            edit: NotebookEdit(range: range, replacement: replacement),
            caret: lineStart + (updated[lineIndex] as NSString).length,
            lineIndex: lineIndex)
    }
}
