import Foundation

/// The intent of one pending user edit, decided from the replacement
/// string AppKit announces before it performs the edit.
///
/// The editor's canonical-format pass must run only for edits that can
/// introduce or rearrange mathematical content. A whitespace-only
/// keystroke (Space, Tab, Enter) is deliberately NOT formatted in that
/// same edit: the literal whitespace stays in the storage and the caret
/// remains right after it. Without this rule a unit conversion typed
/// character by character could never be entered — the space after `5`
/// would be stripped immediately and the next letter would glue into a
/// magnitude suffix (`5m` = 5,000,000 instead of the intended
/// `5 m to cm` = 500 cm). The following non-whitespace edit resumes
/// normal canonicalization, and pure deletions still never reformat.
public enum EditIntent: Equatable, Sendable {
    /// No replacement text: Backspace, delete, cut, or a programmatic
    /// storage rewrite. The document is left exactly as the user left
    /// it — no format pass.
    case none

    /// A non-empty replacement made only of editor whitespace (space,
    /// tab, newline). The literal characters are preserved in the
    /// storage for this edit and the format pass is skipped.
    case whitespace

    /// A non-empty replacement containing at least one
    /// non-whitespace character (typing a digit, letter or operator,
    /// or a paste). Triggers the canonical format pass.
    case content

    /// Decide the intent of one pending replacement.
    public init(replacement: String?) {
        guard let replacement, !replacement.isEmpty else {
            self = .none
            return
        }
        if replacement.allSatisfy(Self.whereTypedWhitespace) {
            self = .whitespace
        } else {
            self = .content
        }
    }

    /// The deliberately small set of "typed whitespace" the editor
    /// protects: space, tab, LF and CR. Any other character — including
    /// other Unicode space separators — is content and is allowed to be
    /// canonicalized.
    private static func whereTypedWhitespace(_ ch: Character) -> Bool {
        ch == " " || ch == "\t" || ch == "\n" || ch == "\r"
    }
}
