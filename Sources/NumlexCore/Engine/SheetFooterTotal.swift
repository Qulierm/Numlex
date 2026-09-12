import Foundation

/// The persistent bottom-panel Total (the sheet footer under the answer
/// column). This is a DIFFERENT contract from the inline `total`
/// command (`InlineTotal`, section-scoped): the footer is deliberately
/// dimension-agnostic and sums the evaluated scalar MAGNITUDE of every
/// ordinary answer row of the whole sheet, with no unit conversion, no
/// FX normalization, no grouping by dimension and no unit/currency
/// suffix — the result is one plain unitless number.
///
/// Eligibility (exactly once per ordinary answer row):
/// - `.number(value:, unit:, kind:, fraction:)` for ANY unit — unitless,
///   physical units (`2 kg`), weather/temperature, durations and
///   currency-code units — contributes its evaluated `value`.
/// - `.variable` and `.variableInt` (named scalars) contribute their
///   evaluated value.
/// - `.money(value:, code:)` contributes its evaluated output
///   magnitude (`$3` contributes 3).
/// - `.integer` contributes its exact value.
/// - Token-derived ordinary rows and duplicate answer references each
///   count once (rows are counted, never dependency-DAG deduplicated).
///
/// Excluded, because they are not a single scalar-number answer, or to
/// avoid double-counting:
/// - `.boolean`, `.date`, `.location`, `.dms`;
/// - `.blank`, `.skip`, `.title`, `.brokenToken`, `.error`;
/// - every row whose `SheetLine.isTotal == true` (an inline `total`
///   command already presents that section's sum — including it here
///   would double-count it).
///
/// Values are the CANONICAL evaluated ones: never display strings and
/// never per-row presentation/rounding overrides. A percent stores its
/// ratio (`25%` contributes 0.25), a multiplier its factor (`1.5x`
/// contributes 1.5), a fraction its numeric value, a money/unit row the
/// output magnitude the answer presents.
///
/// Overflow and precision: a contribution must be FINITE, so a
/// non-finite evaluator value makes its row ineligible (defensive — the
/// engine boundaries already reject non-finite results). The aggregate
/// is a left-to-right `Double` fold, so finite inputs can still overflow
/// to ±∞; that is deterministic and the footer formats it safely through
/// the shared display formatter (`+∞`/`-∞`) instead of trapping. Exact
/// Int64 rows (`.integer`, `.variableInt`) are projected with
/// `Double(value)` — exact while `|value| <= 2^53`, the same documented
/// projection the inline Total uses; base/bitwise/hex evaluation itself
/// stays in the exact Int64 lane and never routes through `Double`.
public enum SheetFooterTotal {
    /// The footer contribution of one evaluated result, or nil when the
    /// row never contributes. `isTotalRow` excludes derived inline
    /// `total` rows so the footer can never double-count one.
    public static func contribution(of result: LineResult, isTotalRow: Bool) -> Double? {
        guard !isTotalRow else { return nil }
        switch result {
        case .number(let v, _, _, _):
            return v.isFinite ? v : nil
        case .variable(_, let v, _, _):
            return v.isFinite ? v : nil
        case .money(let v, _):
            return v.isFinite ? v : nil
        case .integer(let v, _):
            return Double(v)
        case .variableInt(_, let v, _):
            return Double(v)
        case .clock, .laptime:
            // Temporal values are never numeric: they never enter a total.
            return nil
        case .blank, .skip, .title, .boolean, .date, .location, .dms,
             .brokenToken, .error:
            return nil
        }
    }

    /// The footer contribution of one evaluated row.
    public static func contribution(of line: SheetLine) -> Double? {
        contribution(of: line.result, isTotalRow: line.isTotal)
    }

    /// The whole-sheet footer total: nil when there were NO eligible
    /// scalar rows (nothing to display), 0 when eligible rows sum to
    /// zero. One O(n) pass, rows counted in display order — never
    /// dependency-DAG deduplicated, inline total rows excluded.
    public static func aggregate(_ lines: [SheetLine]) -> Double? {
        var sum: Double = 0
        var eligible = 0
        for line in lines {
            guard let c = contribution(of: line) else { continue }
            eligible += 1
            sum += c
        }
        return eligible == 0 ? nil : sum
    }

    /// How many rows of the sheet contribute to the footer total. The
    /// footer is a fold over exactly these rows; exposed so callers and
    /// tests can distinguish "no eligible rows" (nil total) from
    /// "eligible rows summing to zero" (0 total) without rescanning.
    public static func eligibleRowCount(_ lines: [SheetLine]) -> Int {
        lines.reduce(0) { $0 + (contribution(of: $1) == nil ? 0 : 1) }
    }
}
