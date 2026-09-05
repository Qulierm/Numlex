import Foundation

/// Inline `total` rows (r57, refined r58): a standalone `total` line
/// sums the evaluated values of the eligible rows in its SECTION —
/// the rows since the preceding `total`, or from sheet start when
/// there is none — and renders its answer semibold with a gray rule
/// above it.
///
/// Semantics (r58 section subtotals, user-corrected):
/// - The keyword is exactly ASCII `total`, case-insensitive, with
///   outer spaces/tabs allowed. `subtotal`, `total:`, `total + 5`,
///   prose, comments and headings never trigger. Source is never
///   rewritten and `total` is not reserved globally: an ACTIVE
///   variable or global constant named `total`
///   (`TypedEnv.entry(display:)` canonical lookup) takes precedence,
///   so `total = 5` stays an ordinary assignment.
/// - Section-scoped: every recognized total command returns the
///   current section sum and then RESETS the accumulator to zero, so
///   the next section starts empty. A blank, a heading, prose or an
///   error row never resets (and never contributes); only a total
///   command is a section boundary. Each eligible answer row
///   contributes ONCE (row sum, not dependency-DAG deduplication):
///   finite unitless `.number` and `.variable` values, including
///   token-derived scalar rows. Money, unit-bearing quantities
///   (weather included), dates and inactive tokens never contribute.
///   A prior total row never enters a new section, but an ordinary
///   later reference TO a total is an ordinary result row of ITS
///   section and contributes normally. An empty section totals 0, and
///   consecutive totals yield the section sum once and then 0.
///   No conversion/FX/units aggregation.
/// - The aggregate uses EVALUATED numeric values (never display
///   strings or per-row rounding overrides) under the engine's
///   precision conventions. Overflow poisons the CURRENT section
///   only: that section's total is the deterministic quiet generic
///   error — never a fabricated zero or partial total, never
///   NaN/inf, never a crash — and the boundary still resets, so the
///   NEXT section starts fresh with no partial carry.
/// - A ready total is an ordinary `.number(value:, unit: nil)` for
///   Copy, the 0...10 dp slider, Delete Line, live tokens, hover and
///   previous-answer planning; the derived presentation flag rides
///   separately on `SheetLine.isTotal` (defaulted, never persisted).
/// - Accumulation is O(n): both sheet loops feed one shared
///   `TotalAccumulator` top-down instead of rescanning prefixes.
///   The persistent bottom-panel Total is deliberately NOT sectioned:
///   it keeps summing every ordinary unitless row of the whole sheet
///   (total rows excluded), so section subtotals never double-count.
public enum InlineTotal {
    /// Whether the logical line is a total command in the CURRENT
    /// environment: the strict standalone shape, suppressed whenever
    /// the environment holds an active entry named `total` (variable
    /// or immutable constant, canonical case/whitespace lookup).
    /// Standalone `evalLine` has no sheet context, so the command is
    /// recognized only by the sheet loops that own an accumulator —
    /// `evalLineTyped` keeps returning nil here (quiet skip) exactly
    /// as before, and the classifier leaves the keyword base text.
    public static func isCommand(_ line: String, env: TypedEnv) -> Bool {
        guard line.trimmingCharacters(in: .whitespaces).lowercased() == "total" else {
            return false
        }
        return env.entry(display: "total") == nil
    }

    /// The eligible contribution of one evaluated row, or nil when the
    /// row never contributes. Total rows are excluded by the caller
    /// via `isTotalRow` so a total can never double-count an earlier
    /// total (direct ordinary references to a total line are ordinary
    /// rows and contribute normally).
    public static func contribution(of result: LineResult, isTotalRow: Bool) -> Double? {
        guard !isTotalRow else { return nil }
        switch result {
        case .number(let v, nil) where v.isFinite:
            return v
        case .variable(_, let v) where v.isFinite:
            return v
        default:
            return nil
        }
    }

    /// The generic hidden error of an overflowing aggregate — the same
    /// quiet message every other strict failure uses (renders nothing,
    /// offers no menu, breaks dependent tokens deterministically).
    public static let overflowMessage = "Invalid expression"
}

/// The O(n) running SECTION aggregate owned by ONE sheet pass. Both
/// `evaluateSheet` and `resolveSheet` feed rows top-down in their
/// existing sequential loops: observe every completed row, resolve
/// each total command against its section only, then reset.
public struct TotalAccumulator: Sendable {
    private var sum: Double = 0
    private var overflowed: Bool = false

    public init() {}

    /// Feeds one evaluated row into the section sum. Non-finite
    /// arithmetic poisons the CURRENT section — its total errors
    /// rather than fabricating a partial sum — while the boundary
    /// reset below keeps later sections independent.
    public mutating func observe(result: LineResult, isTotalRow: Bool) {
        guard !overflowed,
              let c = InlineTotal.contribution(of: result, isTotalRow: isTotalRow) else {
            return
        }
        let next = sum + c
        guard next.isFinite else {
            overflowed = true
            return
        }
        sum = next
    }

    /// Resolves one total command and RESETS the section: the rounded
    /// section sum, 0 for an empty section (even an empty reset), or
    /// the quiet generic error when the section overflowed. The reset
    /// always happens — an overflow never carries a partial sum into
    /// the next section. Never mutates the environment.
    public mutating func total(decimalPlaces: Int) -> LineResult {
        defer { sum = 0; overflowed = false }
        guard !overflowed else {
            return .error(message: InlineTotal.overflowMessage)
        }
        return .number(value: roundResult(sum, decimalPlaces: decimalPlaces), unit: nil)
    }
}
