import Foundation

/// Package 7: the strict standalone aggregate commands understood by the
/// sheet loops, plus the ONE O(n) accumulator they share.
///
/// - `total`: the legacy section sum (nearest prior legacy total, `# `
///   heading or divider), kept for compatibility.
/// - `subtotal` / `subtotal ± P%` / `<name> = subtotal[ ± P%]`: sum of
///   the eligible rows since the nearest prior SUBTOTAL, `# ` heading
///   or divider. A legacy total is NOT a subtotal boundary.
/// - `grand total` / `<name> = grand total`: the sum of the already
///   computed successful subtotal ROW values above, across the whole
///   sheet (a divider does not erase the grand list). Requires at least
///   two successful subtotals.
public enum SheetAggregateCommand: Equatable, Sendable {
    case legacyTotal
    case subtotal(percent: Double?)
    case namedSubtotal(name: String, percent: Double?)
    case grandTotal
    case namedGrandTotal(name: String)

    /// Parses a strict aggregate command from the tag-stripped
    /// evaluation body. `env` shadows the BARE keywords exactly like
    /// the legacy `total` (an active variable/constant of the same name
    /// wins); the named `= …` form always follows keyword precedence.
    public static func parse(_ line: String, env: TypedEnv,
                             context: NumberFormatContext = .legacy) -> SheetAggregateCommand? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        // Named form first: `<valid name> = subtotal|grand total`.
        if let split = BooleanLogic.assignmentSplit(line) {
            let lhs = split.lhs.trimmingCharacters(in: .whitespaces)
            guard isValidName(lhs) else { return nil }
            if let rhs = subtotalRHS(split.rhs, context: context) {
                return .namedSubtotal(name: lhs, percent: rhs)
            }
            if isGrandTotalBody(split.rhs) {
                return .namedGrandTotal(name: lhs)
            }
            return nil
        }
        // Bare forms, shadowed by an active entry of the same name.
        if env.entry(display: "subtotal") == nil {
            if let percent = subtotalRHS(trimmed, context: context) {
                return .subtotal(percent: percent)
            }
        }
        if env.entry(display: "grand total") == nil, isGrandTotalBody(trimmed) {
            return .grandTotal
        }
        return nil
    }

    /// `subtotal` or `subtotal + R%` / `subtotal - R%`. nil = not this
    /// shape. The percent is returned as a RATIO (15% -> 0.15), signed
    /// by the operator (the caller multiplies the raw subtotal).
    static func subtotalRHS(_ raw: String, context: NumberFormatContext) -> Double?? {
        let tokens = raw.trimmingCharacters(in: .whitespaces)
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .map(String.init)
        guard let head = tokens.first, head.lowercased() == "subtotal" else { return nil }
        if tokens.count == 1 { return .some(nil) }
        guard tokens.count == 3, tokens[1] == "+" || tokens[1] == "-",
              let ratio = FinancialPhraseLane.parsePercent(tokens[2], context: context),
              ratio.isFinite else {
            return nil
        }
        return .some(tokens[1] == "-" ? -ratio : ratio)
    }

    static func isGrandTotalBody(_ raw: String) -> Bool {
        let tokens = raw.trimmingCharacters(in: .whitespaces)
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .map(String.init)
        return tokens.count == 2
            && tokens[0].lowercased() == "grand"
            && tokens[1].lowercased() == "total"
    }

    /// The assignment LHS grammar the evaluator uses: a valid ASCII
    /// identifier or a bounded natural name.
    static func isValidName(_ lhs: String) -> Bool {
        if isValidIdentifier(lhs) { return true }
        return NaturalCalculation.naturalLHS(lhs) != nil
    }
}

/// Package 7: the ONE O(n) sheet aggregate state shared by
/// `evaluateSheet` and `resolveSheet`. It keeps the legacy-total
/// section, the subtotal section and the grand list in one pass.
public struct SheetAggregateState: Sendable {
    private var legacySum: Double = 0
    private var legacyOverflow = false
    /// Package 7: sticky dynamic taint of the current section — set by
    /// any observed row whose result depended on rand, so a subtotal /
    /// legacy total/reference fed by a dynamic row is itself dynamic.
    private var legacyDynamic = false
    private var subtotalSum: Double = 0
    private var subtotalOverflow = false
    private var subtotalDynamic = false
    /// Raw values of the SUCCESSFUL subtotal rows (the grand list is not
    /// erased by a divider); each keeps its dynamic taint so `grand
    /// total` is dynamic when any subtotal it sums is dynamic.
    private var grandValues: [(value: Double, dynamic: Bool)] = []

    public init() {}

    /// Package 7 eligibility, source-aware (the user's stated contract,
    /// shared by the legacy inline total and every new aggregate):
    /// finite unitless plain/fraction/percent/multiplier scalars, exact
    /// integers and named scalar USAGE rows (a bare variable reference,
    /// or a variable used inside a genuine expression). Excluded:
    /// declarations (`x = …`), bare-token-only rows, money, unit-bearing
    /// quantities, boolean/date/time/geo rows, errors and every derived
    /// aggregate row.
    public static func contribution(of result: LineResult,
                                    projection: String) -> Double? {
        let body = projection.trimmingCharacters(in: .whitespaces)
        // A bare answer-token-only row never contributes.
        if body == String(answerTokenMarker) { return nil }
        // A declaration never contributes, whatever its result kind.
        if BooleanLogic.assignmentSplit(body) != nil { return nil }
        switch result {
        case .number(let v, nil, let kind, _) where v.isFinite:
            switch kind {
            case .duration, .timespan, .timecodeSeconds:
                return nil
            case .plain, .fraction, .percent, .multiplier:
                return v
            }
        case .variable(_, let v, _, _) where v.isFinite:
            // A named scalar USAGE row (declarations returned above).
            return v
        case .integer(let v, _):
            return Double(v)
        case .variableInt(_, let v, _):
            return Double(v)
        default:
            return nil
        }
    }

    /// Feeds one completed row into both sections. Derived rows
    /// (legacy totals, subtotals, grand totals, tag aggregates,
    /// dividers, dynamic rows) must pass `isDerived: true`.
    public mutating func observe(result: LineResult, projection: String,
                                 isDerived: Bool, isDynamic: Bool = false) {
        guard !isDerived,
              let c = Self.contribution(of: result, projection: projection) else {
            return
        }
        if isDynamic {
            legacyDynamic = true
            subtotalDynamic = true
        }
        add(c, to: &legacySum, overflow: &legacyOverflow)
        add(c, to: &subtotalSum, overflow: &subtotalOverflow)
    }

    /// A `# ` heading or an exact `---` divider: both sections restart;
    /// the grand list is deliberately untouched.
    public mutating func boundary() {
        legacySum = 0
        legacyOverflow = false
        legacyDynamic = false
        subtotalSum = 0
        subtotalOverflow = false
        subtotalDynamic = false
    }

    /// The legacy `total` command: resolves and resets ONLY the legacy
    /// section (a subtotal is not a legacy boundary).
    public mutating func resolveLegacyTotal(decimalPlaces: Int)
        -> (result: LineResult, isDynamic: Bool) {
        let dynamic = legacyDynamic
        defer {
            legacySum = 0
            legacyOverflow = false
            legacyDynamic = false
        }
        guard !legacyOverflow else {
            return (.error(message: InlineTotal.overflowMessage), dynamic)
        }
        return (.number(value: roundResult(legacySum, decimalPlaces: decimalPlaces),
                        unit: nil),
                dynamic)
    }

    /// The `subtotal[ ± P%]` command: resolves and resets the subtotal
    /// section (even when it overflowed). It does NOT record a grand
    /// value: the caller records ONLY after the command's FINAL row
    /// result is a successful subtotal number and any named-assignment
    /// validation succeeded (a named subtotal assigning to an immutable
    /// constant is an ERROR row and never a successful subtotal).
    /// Returns the row result, the raw subtotal value (nil on overflow)
    /// and the section's dynamic taint.
    public mutating func resolveSubtotal(percent: Double?,
                                         decimalPlaces: Int) -> (result: LineResult,
                                                                 raw: Double?,
                                                                 isDynamic: Bool) {
        let dynamic = subtotalDynamic
        defer {
            subtotalSum = 0
            subtotalOverflow = false
            subtotalDynamic = false
        }
        guard !subtotalOverflow else {
            return (.error(message: InlineTotal.overflowMessage), nil, dynamic)
        }
        let base = subtotalSum
        let raw = percent.map { base * (1 + $0) } ?? base
        guard raw.isFinite else {
            return (.error(message: InlineTotal.overflowMessage), nil, dynamic)
        }
        return (.number(value: roundResult(raw, decimalPlaces: decimalPlaces), unit: nil),
                raw,
                dynamic)
    }

    /// Records a SUCCESSFUL subtotal row's raw value for `grand total`.
    /// Called by the command resolver only after the final result
    /// (constant validation included) succeeded; the dynamic taint
    /// rides with the value. An overflowed subtotal never reaches this
    /// call (its raw value is nil).
    public mutating func recordGrandValue(_ raw: Double, isDynamic: Bool) {
        guard raw.isFinite else { return }
        grandValues.append((value: raw, dynamic: isDynamic))
    }

    /// The `grand total` command: the sum of the successful subtotal row
    /// values above. Fewer than two subtotals is the quiet generic
    /// error. The grand list is never erased. Dynamic when any subtotal
    /// it sums is dynamic.
    public mutating func resolveGrandTotal(decimalPlaces: Int)
        -> (result: LineResult, isDynamic: Bool) {
        let dynamic = grandValues.contains { $0.dynamic }
        guard grandValues.count >= 2 else {
            return (.error(message: InlineTotal.overflowMessage), dynamic)
        }
        var sum = 0.0
        for entry in grandValues {
            let next = sum + entry.value
            guard next.isFinite else {
                return (.error(message: InlineTotal.overflowMessage), dynamic)
            }
            sum = next
        }
        return (.number(value: roundResult(sum, decimalPlaces: decimalPlaces), unit: nil),
                dynamic)
    }

    /// How many successful subtotal rows exist (tests/diagnostics).
    public var successfulSubtotalCount: Int { grandValues.count }

    private func add(_ c: Double, to sum: inout Double, overflow: inout Bool) {
        guard !overflow else { return }
        let next = sum + c
        guard next.isFinite else {
            overflow = true
            return
        }
        sum = next
    }
}

/// Package 7: the ONE command resolver shared by `evaluateSheet` and
/// `resolveSheet`. Resolves the command against the shared aggregate
/// state, performs the optional named assignment (never mutating a
/// constant) and returns the row result plus its derived metadata.
func resolveAggregateCommand(_ command: SheetAggregateCommand,
                             env: inout TypedEnv,
                             aggregate: inout SheetAggregateState,
                             decimalPlaces: Int) -> (result: LineResult,
                                                     metadata: SheetLineMetadata,
                                                     isDynamic: Bool) {
    switch command {
    case .legacyTotal:
        let r = aggregate.resolveLegacyTotal(decimalPlaces: decimalPlaces)
        return (r.result, .legacyTotal, r.isDynamic)
    case .subtotal(let percent), .namedSubtotal(_, let percent):
        let (result, raw, dynamic) = aggregate.resolveSubtotal(percent: percent,
                                                               decimalPlaces: decimalPlaces)
        var finalResult = result
        var recordGrand = false
        if case .namedSubtotal(let name, _) = command {
            if env.isConstant(display: name) {
                // The FINAL row is an error: never a successful subtotal
                // row, so it is not recorded for `grand total` (the
                // section boundary reset already happened above).
                finalResult = .error(message: "Cannot assign to constant")
            } else if let raw {
                // The final plain scalar (the raw, unrounded value).
                env.set(display: name, qty: .scalar(raw))
                recordGrand = true
            }
        } else if case .number = result, raw != nil {
            recordGrand = true
        }
        if recordGrand, let raw {
            aggregate.recordGrandValue(raw, isDynamic: dynamic)
        }
        return (finalResult, .subtotal, dynamic)
    case .grandTotal, .namedGrandTotal:
        let r = aggregate.resolveGrandTotal(decimalPlaces: decimalPlaces)
        var finalResult = r.result
        if case .namedGrandTotal(let name) = command {
            if env.isConstant(display: name) {
                finalResult = .error(message: "Cannot assign to constant")
            } else if case .number(let v, _, _, _) = finalResult {
                env.set(display: name, qty: .scalar(v))
            }
        }
        return (finalResult, .grandTotal, r.isDynamic)
    }
}
