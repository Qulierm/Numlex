import Foundation

/// The Floating Total contribution policy (General Settings → Floating
/// Total). The DEFAULT policy reproduces every earlier build's footer
/// byte-for-byte: referenced source rows and named-scalar declarations
/// both contribute.
///
/// "Referenced line" means a source line whose stable ID is named by an
/// `AnswerReference.sourceLineID` — the source of a token, NOT the row
/// that shows the token. Excluding them removes the source rows while the
/// token-carrying consumer row keeps contributing.
public struct FooterContributionPolicy: Equatable, Sendable {
    /// Include the source rows of answer tokens.
    public var includeReferencedLines: Bool
    /// Include `.variable` / `.variableInt` declaration rows.
    public var includeVariableDeclarations: Bool

    /// The default policy = the historical footer exactly.
    public static let defaults = FooterContributionPolicy()

    public init(includeReferencedLines: Bool = true,
                includeVariableDeclarations: Bool = true) {
        self.includeReferencedLines = includeReferencedLines
        self.includeVariableDeclarations = includeVariableDeclarations
    }
}
