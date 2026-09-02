import Foundation

/// The PURE, deterministic resolver for global user constants (r33).
/// No UI, no persistence sidecar, no global state: the input row order
/// is the only ordering source, dependencies resolve independent of
/// row order (topological fixed point), and every row always carries a
/// stable status — invalid rows stay present but INACTIVE (they reserve
/// no name and are never referenced).
///
/// Accepted values (the existing strict expression/money grammar, NO
/// blind word stripping):
/// - finite unitless scalars: `3.141592653589793`, `(1 + 2) × 4`,
///   `sqrt(2) × PI` — anything the shared expression engine evaluates
///   (r47: the built-in math functions are available as arguments);
/// - percentages: `20%` (postfix percent, a plain scalar 0.2);
/// - single-fiat-code money: `$2,500`, `CA$100`, `Rp25000`, `€50 + 5`;
/// - references to other (eventually valid) constants, in ANY row
///   order: `Tau = PI × 2`, `Annual Rent = Monthly Rent × 12`.
///
/// Explicitly REJECTED (hidden invalid, never partially stripped):
/// unit-bearing values (`9.81 m/s²`, `10 km`), rate conversions
/// (`Monthly Rent in EUR`), dates (`today + 1`), assignments
/// (`x = 5`), reference-token markers (U+FFFC), mixed currencies,
/// non-finite/overflow results, unknown identifiers, self-reference
/// and cycles.
public enum ConstantResolver {

    public static let maxRows = 100
    public static let maxNameLength = 40
    public static let maxExpressionLength = 256

    // MARK: Generated names

    /// Deterministic name for a fresh constant row: `constant`, then
    /// `constant_2`, `constant_3`, … — the first candidate whose
    /// CANONICAL key (case/whitespace-insensitive) is not in `taken`.
    /// Every generated name satisfies the shared name grammar
    /// (`NaturalCalculation.naturalLHS`); the r33 `constant 2` scheme
    /// violated it (a digit-first word), so such rows were born
    /// invalid. Existing rows are never rewritten by this.
    public static func generatedConstantName(taken: Set<String>) -> String {
        if !taken.contains(canonicalNameKey("constant")) { return "constant" }
        var n = 2
        while true {
            let candidate = "constant_\(n)"
            if !taken.contains(canonicalNameKey(candidate)) { return candidate }
            n += 1
        }
    }

    // MARK: Status

    /// The stable per-row status. `valid` carries the resolved
    /// quantity (full engine precision — display rounding happens only
    /// at presentation time).
    public enum RowStatus: Equatable, Sendable {
        case valid(TypedQty)
        /// Neither name nor expression typed (a fresh row).
        case empty
        /// Exactly one of name/expression is typed.
        case incomplete
        /// The name is empty of grammar (not 1–6 bounded ASCII words)
        /// or longer than 40 characters.
        case invalidName
        /// Two or more rows share the same case/whitespace-insensitive
        /// name: ALL colliding rows are inactive.
        case duplicate
        /// The name collides with a reserved unit/currency/date/grammar
        /// token.
        case reserved
        /// The expression cannot parse (bad syntax, rejected shape,
        /// non-finite/overflow) or fails the money pipeline.
        case invalidExpression
        /// The expression references an identifier that is not an
        /// active constant (unknown, or a name an inactive row would
        /// hold).
        case invalidDependency
        /// Self-reference, a dependency cycle, or a reference to a
        /// cycle member: the row can never resolve.
        case cycle
        /// Row beyond the 100-row limit (corrupt payloads only — the
        /// UI cannot create them).
        case exceedsLimit
    }

    /// One resolved row, in the input order.
    public struct ResolvedRow: Equatable, Sendable {
        public let id: UUID
        public let name: String
        public let expression: String
        public let status: RowStatus
        public init(id: UUID, name: String, expression: String, status: RowStatus) {
            self.id = id
            self.name = name
            self.expression = expression
            self.status = status
        }
    }

    /// The deterministic resolution of one constant list.
    public struct Resolution: Equatable, Sendable {
        public let rows: [ResolvedRow]
        public init(rows: [ResolvedRow]) { self.rows = rows }

        /// Valid entries in INPUT ORDER (never dictionary order):
        /// display name plus resolved quantity.
        public var entries: [(display: String, qty: TypedQty)] {
            rows.compactMap { row in
                if case .valid(let q) = row.status { return (row.name, q) }
                return nil
            }
        }
    }

    // MARK: Reserved names

    /// The reserved NAME set (canonical keys): exact UnitCatalog unit
    /// labels/aliases, currency codes and English currency aliases,
    /// grammar/date tokens (`to`, `in`, `of`, `per`, `as`,
    /// today/tomorrow/yesterday, month names, duration words). Ordinary
    /// words are NOT reserved: `tax`, `PI`, `Sales Tax` all work.
    static let reservedKeys: Set<String> = {
        var s = Set<String>()
        for w in ["to", "in", "of", "per", "as",
                  "today", "tomorrow", "yesterday"] {
            s.insert(canonicalNameKey(w))
        }
        for w in DateArithmetic.monthIndex.keys { s.insert(canonicalNameKey(w)) }
        for w in DateArithmetic.durationWords.keys { s.insert(canonicalNameKey(w)) }
        for def in UnitCatalog.all {
            s.insert(canonicalNameKey(def.label))
            for a in def.aliases { s.insert(canonicalNameKey(a)) }
        }
        for code in FiatCurrencies.codes { s.insert(canonicalNameKey(code)) }
        for aliases in FiatCurrencies.aliases.values {
            for a in aliases { s.insert(canonicalNameKey(a)) }
        }
        return s
    }()

    /// Whether a display name is reserved (case/whitespace-insensitive).
    public static func isReservedName(_ display: String) -> Bool {
        reservedKeys.contains(canonicalNameKey(display))
    }

    // MARK: Resolve

    /// Resolves the full constant list. Deterministic in the input row
    /// order; repeated calls on equal input return equal results.
    public static func resolve(_ constants: [UserConstant]) -> Resolution {
        let rows = constants
        let n = rows.count
        var status: [RowStatus] = Array(repeating: .empty, count: n)
        // Row -> canonical display name (only rows whose NAME passed).
        var display: [Int: String] = [:]
        var keyCounts: [String: Int] = [:]

        // --- Stage 1: name validation --------------------------------
        for i in 0..<n {
            if i >= maxRows { status[i] = .exceedsLimit; continue }
            let name = rows[i].name.trimmingCharacters(in: .whitespaces)
            let expr = rows[i].expression.trimmingCharacters(in: .whitespaces)
            if name.isEmpty && expr.isEmpty { status[i] = .empty; continue }
            if name.isEmpty || expr.isEmpty { status[i] = .incomplete; continue }
            guard name.count <= maxNameLength,
                  let canonical = NaturalCalculation.naturalLHS(name) else {
                status[i] = .invalidName
                continue
            }
            if reservedKeys.contains(canonicalNameKey(canonical)) {
                status[i] = .reserved
                continue
            }
            if expr.count > maxExpressionLength {
                status[i] = .invalidExpression
                continue
            }
            // Assignment is never a value expression.
            if expr.contains("=") {
                status[i] = .invalidExpression
                continue
            }
            let key = canonicalNameKey(canonical)
            display[i] = canonical
            keyCounts[key, default: 0] += 1
        }
        // Case/whitespace duplicates: every colliding row is inactive.
        for i in 0..<n where display[i] != nil {
            if keyCounts[canonicalNameKey(display[i]!)]! > 1 { status[i] = .duplicate }
        }
        // Rows past the limit keep the limit status even if their name
        // failed a stage-1 check (deterministic precedence).
        if n > maxRows {
            for i in maxRows..<n { status[i] = .exceedsLimit }
        }

        // --- Stage 2: dependency graph + fixed point ------------------
        // "name-OK" rows are name-valid, unique, non-reserved: they
        // participate in dependency resolution.
        let nameOK: [Bool] = (0..<n).map {
            display[$0] != nil && status[$0] != .duplicate
        }

        // The declared environment: every name-OK row gets an entry —
        // resolved rows carry their real quantity, not-yet-resolved
        // rows a dummy (matching uses the name, never the value).
        var resolvedEnv = TypedEnv()
        var resolvedKeys: Set<String> = []
        var undecided = Set(0..<n).filter { nameOK[$0] }

        func declaredEnv(_ resolved: TypedEnv) -> TypedEnv {
            var d = resolved
            for i in sorted(undecided) {
                d.set(display: display[i]!, qty: .scalar(0))
            }
            return d
        }

        var progress = true
        while progress {
            progress = false
            // Recomputed per row: a sibling that FAILED earlier in this
            // pass must not still look "declared" to the rows after it.
            for i in sorted(undecided) {
                let declared = declaredEnv(resolvedEnv)
                let expr = rows[i].expression
                let unresolvedKeys = Set(
                    sorted(undecided).map { canonicalNameKey(display[$0]!) })
                let (pending, unknown) = referenceInfo(
                    expr: expr, declared: declared, unresolvedKeys: unresolvedKeys)
                if unknown {
                    status[i] = .invalidDependency
                    undecided.remove(i)
                    progress = true
                    continue
                }
                if pending { continue }
                // All references resolved: evaluate strictly.
                if let qty = evaluateValue(expr, env: resolvedEnv) {
                    status[i] = .valid(qty)
                    resolvedEnv.setConstant(display: display[i]!, qty: qty)
                    resolvedKeys.insert(canonicalNameKey(display[i]!))
                } else {
                    status[i] = .invalidExpression
                }
                undecided.remove(i)
                progress = true
            }
        }
        _ = resolvedKeys

        // --- Stage 3: leftover rows -----------------------------------
        // A leftover still references name-OK rows that never resolved:
        // either a dependency on an inactive row (invalidDependency) or
        // a cycle / cycle downstream (cycle).
        let leftover = sorted(undecided)
        if !leftover.isEmpty {
            for i in leftover {
                let unresolvedKeys = Set(leftover.map { canonicalNameKey(display[$0]!) })
                let declared = declaredEnv(resolvedEnv)
                let matches = NamedValues.matches(in: rows[i].expression, env: declared)
                let depKeys = Set(matches.map { canonicalNameKey($0.entry.display) })
                let hitsInactive = depKeys.contains { key in
                    unresolvedKeys.contains(key) == false
                }
                // depKeys only contains name-OK rows by construction
                // (declaredEnv), so "not in the leftover set" means a
                // row that ended inactive (e.g. invalidExpression).
                status[i] = hitsInactive ? .invalidDependency : .cycle
            }
            undecided.removeAll()
        }

        let resolvedRows = (0..<n).map { i in
            ResolvedRow(id: rows[i].id,
                        name: display[i] ?? rows[i].name.trimmingCharacters(in: .whitespaces),
                        expression: rows[i].expression,
                        status: status[i])
        }
        return Resolution(rows: resolvedRows)
    }

    private static func sorted(_ s: Set<Int>) -> [Int] { s.sorted() }

    // MARK: Reference classification

    /// Classifies the declared-name references and free words of one
    /// expression: `pending` when it still references a not-yet-resolved
    /// constant, `unknown` when a surviving word is not a declared
    /// constant, `of`, a neutral prose word or a time word (the money
    /// grammar's bounded lists). Currency markers and ISO annotations
    /// are never words.
    private static func referenceInfo(
        expr: String,
        declared: TypedEnv,
        unresolvedKeys: Set<String>
    ) -> (pending: Bool, unknown: Bool) {
        let ns = expr as NSString
        let full = NSRange(location: 0, length: ns.length)

        var covered: [NSRange] = []
        var pending = false
        for m in NamedValues.matches(in: expr, env: declared) {
            covered.append(m.range)
            if unresolvedKeys.contains(canonicalNameKey(m.entry.display)) {
                pending = true
            }
        }
        for r in CurrencyPresentation.markerOccurrences(in: expr) {
            covered.append(r)
        }
        // ISO currency annotations: `100 USD` — the code is a value
        // annotation, not a free word.
        if let isoRe = try? NSRegularExpression(
            pattern: #"(?<=[0-9.])[ ]*([A-Z]{3})(?![A-Za-z0-9_])"#) {
            for m in isoRe.matches(in: expr, range: full) where m.numberOfRanges >= 2 {
                let code = ns.substring(with: m.range(at: 1))
                if FiatCurrencies.codes.contains(code) {
                    covered.append(m.range(at: 1))
                }
            }
        }

        guard let wordRe = try? NSRegularExpression(pattern: #"(?<![0-9])[A-Za-z_]\w*"#)
        else { return (pending, false) }
        for m in wordRe.matches(in: expr, range: full) {
            // A word is covered when it lies INSIDE a matched name
            // (a multiword name covers several word runs), a marker or
            // an ISO annotation range.
            if covered.contains(where: { r in
                m.range.location >= r.location && NSMaxRange(m.range) <= NSMaxRange(r)
            }) { continue }
            let lower = ns.substring(with: m.range).lowercased()
            if lower == "of"
                || NaturalCalculation.neutralWords.contains(lower)
                || NaturalCalculation.timeWords.contains(lower) {
                continue
            }
            // r47: a builtin call head is grammar, never a free word:
            // `R = sqrt(4)` must not read `sqrt` as an unknown reference,
            // and a same-named constant used in call position is the
            // builtin (the constant still works in non-call positions).
            if MathFunctions.isKnown(lower) {
                var k = NSMaxRange(m.range)
                while k < full.length, ns.character(at: k) == 0x20 || ns.character(at: k) == 0x09 {
                    k += 1
                }
                if k < full.length, ns.character(at: k) == 0x28 { continue }
            }
            return (pending, true)
        }
        return (pending, false)
    }

    // MARK: Strict evaluation

    /// Evaluates one expression against the RESOLVED constants: the
    /// money grammar when the line carries a currency marker/ISO
    /// annotation, the strict named-expression pipeline otherwise
    /// (no word stripping, no unit parsing).
    static func evaluateValue(_ expr: String, env: TypedEnv) -> TypedQty? {
        switch NaturalCalculation.moneyOutcome(expr, env: env) {
        case .money(let v, let c):
            return .money(v, code: c)
        case .malformed:
            return nil
        case .none:
            guard let (v, codes) = strictScalar(expr, env: env) else { return nil }
            if let c = codes.first { return .money(v, code: c) }
            return .scalar(v)
        }
    }

    /// The strict named-expression evaluation with FULL finite
    /// precision: the SHARED `namedExprCore` (placeholder substitution,
    /// residual identifier guard, `normalizeExprCorrect`,
    /// `evaluateExpression` — no second parser, no word stripping),
    /// WITHOUT the line pipeline's 10-decimal display rounding: stored
    /// constant values keep exactly what the shared engine computes.
    private static func strictScalar(_ expr: String, env: TypedEnv) -> (value: Double, codes: Set<String>)? {
        namedExprCore(expr, env: env)
    }
}

// MARK: - TypedEnv seeding

extension TypedEnv {
    /// Seeds the environment with the RESOLVED global constants
    /// (immutable entries, in deterministic input order). Called once
    /// per evaluation pass, before any logical line.
    public mutating func seedConstants(_ constants: [UserConstant]) {
        for e in ConstantResolver.resolve(constants).entries {
            setConstant(display: e.display, qty: e.qty)
        }
    }
}
