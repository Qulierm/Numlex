import Foundation

/// Explicit conversion-target selection, with SOURCE-AWARE contextual
/// readings.
///
/// An ordinary, unambiguous resolution always wins: the target text is first
/// resolved through the shared unit-expression grammar (which now understands
/// the spelled `per` operator). Only when that reading is INCOMPATIBLE with
/// the evaluated source is a documented contextual shorthand considered, and
/// only when exactly ONE of its readings is compatible — never a guess, never
/// an alias rewrite of the catalog.
///
/// The one contextual entry that exists is deliberately narrow:
///
/// - `ms` ordinarily means the MILLISECOND, globally and everywhere (`500 ms
///   to s`, `1 s to ms`, the glued duration `500ms`, and a millisecond
///   SOURCE all keep that meaning). A speed source cannot convert to a
///   millisecond, so for a speed source the compatible reading of `ms` is
///   metres per second, which is what `5 km per hour to ms` asks for. Any
///   other source (a length, a mass, a currency) stays incompatible: the
///   contextual reading is only accepted when it actually matches the
///   source's dimension and family. The canonical spelling remains `m/s`
///   (or the unambiguous alias `mps`).
public enum UnitTargetResolver {

    /// The documented contextual readings, keyed by the NORMALIZED target
    /// text. Each value is a list of unit-expression texts tried in order
    /// when — and only when — the ordinary reading is incompatible.
    static let contextualTargets: [String: [String]] = [
        "ms": ["m/s"],
    ]

    /// Resolves an explicit conversion target against the evaluated source.
    ///
    /// - Parameters:
    ///   - text: the raw text after the `to|in|as` keyword.
    ///   - source: the evaluated source quantity (nil when the caller cannot
    ///     supply one: the ordinary reading is then returned unchanged).
    ///   - unitContext: the active unit context (custom units included).
    ///   - rates: the currency table, so a currency target's compatibility is
    ///     judged by the same conversion rules the result uses.
    /// - Returns: the target unit, or nil when nothing resolves (the caller
    ///   raises the deterministic hidden error).
    public static func resolve(_ text: String,
                               source: Quantity?,
                               unitContext: UnitContext,
                               rates: Rates) -> UnitExpr? {
        let ordinary = resolveOrdinary(text, unitContext: unitContext)
        guard let source else { return ordinary }
        if let ordinary, isCompatible(ordinary, with: source, rates: rates) {
            return ordinary
        }
        guard let candidates = contextualTargets[UnitCatalog.normalize(text)],
              !candidates.isEmpty else {
            // No contextual reading: the ordinary one (possibly incompatible,
            // possibly nil) is the answer — the conversion itself decides.
            return ordinary
        }
        let compatible = candidates
            .compactMap { resolveOrdinary($0, unitContext: unitContext) }
            .filter { isCompatible($0, with: source, rates: rates) }
        // Exactly one compatible candidate may win; anything else keeps the
        // ordinary reading so the error stays deterministic.
        guard compatible.count == 1 else { return ordinary }
        return compatible[0]
    }

    /// The ordinary resolution: the shared expression grammar first (which
    /// understands `/`, `*`, `per` and every full-expression alias), then a
    /// display label / single-token lookup through the context (custom units
    /// included).
    static func resolveOrdinary(_ text: String, unitContext: UnitContext) -> UnitExpr? {
        if let parsed = unitContext.resolveExpression(text) {
            return parsed.unit
        }
        return unitContext.resolveLabel(text)
    }

    /// True when the source can actually be converted to the target under the
    /// shared conversion rules (dimension signature + family wall + special
    /// finite transforms).
    static func isCompatible(_ target: UnitExpr, with source: Quantity,
                             rates: Rates) -> Bool {
        guard let converted = try? source.converted(to: target, rates: rates).get() else {
            return false
        }
        return converted.value.isFinite
    }
}
