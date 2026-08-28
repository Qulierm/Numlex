import Foundation

/// One GLOBAL user-defined constant (r33). The name follows the same
/// bounded grammar as natural assignment LHS (1–6 ASCII words, ≤ 40
/// chars); the expression is the user's VERBATIM source text — a
/// finite unitless scalar, a percentage, or a single-fiat-code money
/// quantity, possibly referencing other constants. No computed
/// snapshot is ever persisted: values are re-derived by the pure
/// `ConstantResolver` on every evaluation pass, so a settings edit
/// updates every sheet immediately.
public struct UserConstant: Identifiable, Codable, Equatable, Sendable {
    /// Stable row identity: edit bindings and delete target this UUID,
    /// never a fragile array index.
    public let id: UUID
    public var name: String
    public var expression: String

    public init(id: UUID = UUID(), name: String, expression: String) {
        self.id = id
        self.name = name
        self.expression = expression
    }
}
