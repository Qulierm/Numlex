import Foundation

// MARK: - R84: custom unit resolution
//
// `UnitResolver` turns the app-global custom-unit ROWS (name +
// definition source, exactly as the settings UI edits them) into the
// immutable `UnitContext` an evaluation pass consumes. It mirrors the
// `ConstantResolver` contract: deterministic, pure, per pass, and
// failure-proof — a bad row is INACTIVE (it simply does not enter the
// context) while pre-existing built-in units keep working.
//
// A definition is either the literal `new unit` (an independent
// dimension, carried through the `r84custom<axis>` name tag) or
// `<number> <unit expression>` — a linear multiple of existing units
// (built-in or other ACTIVE custom units). Custom definitions resolve
// by fixed-point iteration: each round re-resolves the pending rows
// against the context of everything resolved so far; the loop is
// bounded (`maxRounds`), and rows that can never resolve are classified
// (`cycle` vs `unknownDependency`) from the dependency graph.

public enum UnitResolver {
    /// The app-global custom-unit row limit (the UI enforces it; the
    /// resolver classifies anything beyond it as inactive).
    public static let maxRows = 100
    /// The fixed-point iteration bound (deep dependency chains longer
    /// than this are classified as inactive).
    public static let maxRounds = 100
    /// The name length bound (matches the constant name bound).
    public static let maxNameLength = 40

    /// One resolved row, in the input order.
    public struct ResolvedRow: Equatable, Sendable {
        public let id: UUID
        public let name: String
        public let definition: String
        public let status: CustomUnitStatus
        /// The resolved unit of an ACTIVE row (nil otherwise) — the
        /// settings preview column renders it.
        public let resolved: UnitExpr?
        public init(id: UUID, name: String, definition: String,
                    status: CustomUnitStatus, resolved: UnitExpr? = nil) {
            self.id = id
            self.name = name
            self.definition = definition
            self.status = status
            self.resolved = resolved
        }
    }

    /// The deterministic resolution of one custom-unit list.
    public struct Resolution: Sendable {
        public let rows: [ResolvedRow]
        /// The context of the ACTIVE rows (the value evaluation passes
        /// consume; `.builtIns` when nothing is active).
        public let context: UnitContext
        public init(rows: [ResolvedRow], context: UnitContext) {
            self.rows = rows
            self.context = context
        }
    }

    /// The next free generated unit name (`unit`, `unit2`, …).
    public static func generatedUnitName(taken: Set<String>) -> String {
        let base = "unit"
        if !taken.contains(UnitCatalog.normalize(base)) { return base }
        var i = 2
        while taken.contains(UnitCatalog.normalize(base + String(i))) { i += 1 }
        return base + String(i)
    }

    // MARK: Entry point

    public static func resolve(_ rows: [UserUnitDefinition],
                               constants: [UserConstant] = []) -> Resolution {
        let constantNames = Set(
            constants.map { UnitCatalog.normalize($0.name) }
        )

        // The 100-row limit: anything beyond it is inactive.
        let inLimit = Array(rows.prefix(maxRows))
        let overflow = Array(rows.dropFirst(maxRows))

        // Pass 1: static row grammar (order: limit > empty >
        // incomplete > invalidName > duplicate > builtIn > constant).
        let normalized = inLimit.map { normName($0.name) }
        let nameCounts: [String: Int] = normalized.reduce(into: [:]) {
            $0[$1, default: 0] += 1
        }
        // A name that collides with a built-in token is a collision
        // even when several rows share it (the built-in claim wins).
        var staticStatus: [Int: CustomUnitStatus] = [:]
        for (i, row) in inLimit.enumerated() {
            let name = row.name.trimmingCharacters(in: .whitespaces)
            let def = row.definition.trimmingCharacters(in: .whitespaces)
            staticStatus[i] = staticRowStatus(
                hasName: !name.isEmpty,
                hasDefinition: !def.isEmpty,
                normName: normalized[i],
                isDuplicate: nameCounts[normalized[i]]! > 1,
                isBuiltIn: !normalized[i].isEmpty && isBuiltInName(normalized[i]),
                isConstant: !normalized[i].isEmpty && constantNames.contains(normalized[i])
            )
        }

        // Pass 2: definition validation for the grammatical rows.
        // `defKind` classifies the SOURCE: `.new` is the independent
        // dimension, `.linear(factor, expr)` a multiple, `.invalid` a
        // parse failure (final immediately).
        var defKind: [Int: DefKind] = [:]
        for (i, row) in inLimit.enumerated() where staticStatus[i] == nil {
            defKind[i] = parseDefinition(row.definition)
            if case .invalid = defKind[i]! {
                staticStatus[i] = .invalidDefinition
            }
        }

        // Pass 3: fixed point over the linear rows. New-dimension rows
        // are dependency-free (they claim their axis in input order).
        var active: [Int: ResolvedCustomUnit] = [:]
        // Axis ordinals: assign as new-dimension rows activate, in
        // input order.
        var pending = inLimit.indices.filter { i in
            guard staticStatus[i] == nil else { return false }
            guard let kind = defKind[i] else { return false }
            switch kind {
            case .linear, .new: return true
            case .invalid: return false
            }
        }
        var newDimensionAxis = 0
        var rounds = 0
        while !pending.isEmpty, rounds < maxRounds {
            rounds += 1
            let ctx = UnitContext(customUnits:
                inLimit.indices.compactMap { active[$0] })
            // New-dimension rows activate immediately (in the pending
            // order, which preserves input order).
            let newOnes = pending.filter { defKind[$0] == .new }
            pending = pending.filter { defKind[$0] != .new }
            for i in newOnes {
                let row = inLimit[i]
                let axis = newDimensionAxis
                newDimensionAxis += 1
                let expr = UnitExpr(kind: .factor(.zero, 1), vector: .zero,
                                    family: .none, toBase: 1,
                                    label: row.name.trimmingCharacters(in: .whitespaces),
                                    name: "r84custom\(axis)")
                active[i] = ResolvedCustomUnit(
                    id: row.id, name: row.name.trimmingCharacters(in: .whitespaces),
                    definition: row.definition.trimmingCharacters(in: .whitespaces),
                    expr: expr, inputAliases: aliases(for: row.name, ctx: ctx),
                    axis: axis)
            }
            // Linear rows: resolve against the current context.
            var nextPending: [Int] = []
            for i in pending {
                guard let kind = defKind[i], case .linear(let factor, let exprText) = kind
                else { continue }
                guard let pe = ctx.resolveExpression(exprText),
                      pe.unit.isLinear, !pe.isSpecial else {
                    nextPending.append(i)
                    continue
                }
                let u = pe.unit
                let factor2 = factor * u.toBase
                guard factor2.isFinite, factor2 > 0 else {
                    staticStatus[i] = .nonFinite
                    continue
                }
                let row = inLimit[i]
                let name = row.name.trimmingCharacters(in: .whitespaces)
                let resolved = UnitExpr(
                    kind: .factor(u.vector, factor2), vector: u.vector,
                    family: u.family, toBase: factor2, label: name, name: name)
                active[i] = ResolvedCustomUnit(
                    id: row.id, name: name,
                    definition: row.definition.trimmingCharacters(in: .whitespaces),
                    expr: resolved, inputAliases: aliases(for: name, ctx: ctx),
                    axis: nil)
            }
            // A stall only counts when nothing NEW (new-dimension row)
            // activated this round either: a freshly activated unit can
            // unblock the linear rows on the NEXT round.
            if nextPending.count == pending.count, newOnes.isEmpty {
                // Nothing activated this round: classify the remainder
                // from the dependency graph (cycle vs unknown).
                let activeNames = Set(active.values.flatMap { $0.inputAliases })
                for i in pending {
                    staticStatus[i] = classifyPending(deps: [], active: activeNames,
                                                      rows: inLimit)
                }
                pending = []
            } else {
                pending = nextPending
            }
        }
        if !pending.isEmpty {
            // The round bound fired before convergence: inactive.
            for i in pending { staticStatus[i] = .exceedsLimit }
        }

        // Assemble the row statuses in input order.
        var resolvedRows: [ResolvedRow] = []
        for (i, row) in inLimit.enumerated() {
            let status: CustomUnitStatus
            if let s = staticStatus[i] {
                status = s
            } else if active[i] != nil {
                status = .active
            } else {
                status = .unknownDependency
            }
            resolvedRows.append(ResolvedRow(id: row.id, name: row.name,
                                            definition: row.definition,
                                            status: status,
                                            resolved: active[i]?.expr))
        }
        for row in overflow {
            resolvedRows.append(ResolvedRow(id: row.id, name: row.name,
                                            definition: row.definition,
                                            status: .exceedsLimit))
        }
        let context = UnitContext(customUnits:
            inLimit.indices.compactMap { active[$0] })
        return Resolution(rows: resolvedRows, context: context)
    }

    // MARK: Pass 1

    static func staticRowStatus(hasName: Bool, hasDefinition: Bool,
                                normName: String, isDuplicate: Bool,
                                isBuiltIn: Bool, isConstant: Bool)
        -> CustomUnitStatus? {
        if !hasName && !hasDefinition { return .empty }
        if hasName != hasDefinition { return .incomplete }
        if normName.isEmpty || !nameGrammar(normName) { return .invalidName }
        if isDuplicate { return .duplicate }
        if isBuiltIn { return .builtInCollision }
        if isConstant { return .constantCollision }
        return nil
    }

    /// Names are 1–`maxNameLength` normalized characters of letters
    /// (incl. accented letters and Cyrillic/CJK), spaces and hyphens —
    /// no digits, operators or punctuation.
    static func nameGrammar(_ normName: String) -> Bool {
        guard normName.count <= maxNameLength, !normName.isEmpty else { return false }
        for scalar in normName.unicodeScalars {
            let ok = CharacterSet.letters.contains(scalar)
                || scalar == " " || scalar == "-" || scalar == "’"
            if !ok { return false }
        }
        return true
    }

    public static func normName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let lowered = trimmed.lowercased()
        return UnitCatalog.normalize(lowered)
    }

    /// A name (or its singular) that a built-in unit or label already
    /// claims.
    static func isBuiltInName(_ normName: String) -> Bool {
        guard !normName.isEmpty else { return false }
        if UnitCatalog.resolveToken(normName) != nil { return true }
        if UnitCatalog.resolveLabel(normName) != nil { return true }
        if normName.hasSuffix("s"), normName.count > 2 {
            let singular = String(normName.dropLast())
            if UnitCatalog.resolveToken(singular) != nil
                || UnitCatalog.resolveLabel(singular) != nil { return true }
        }
        return false
    }

    // MARK: Definition parsing

    enum DefKind: Equatable {
        case new
        case linear(factor: Double, expr: String)
        case invalid
    }

    static func parseDefinition(_ source: String) -> DefKind {
        let src = source.trimmingCharacters(in: .whitespaces)
        guard !src.isEmpty else { return .invalid }
        if src.lowercased() == "new unit" { return .new }
        // `<number> <expression>`: the leading run is digits with the
        // regional separators, then a space, then the unit text.
        var i = src.startIndex
        var digits = 0
        var separators = 0
        while i < src.endIndex {
            let c = src[i]
            if c.isNumber {
                digits += 1
                i = src.index(after: i)
            } else if c == "." || c == "," {
                separators += 1
                i = src.index(after: i)
            } else {
                break
            }
        }
        guard digits > 0, separators <= 2 else { return .invalid }
        let numberText = String(src[..<i])
        // A space is required before the unit text (glued `660feet`
        // is not a definition).
        guard i < src.endIndex, src[i] == " " else { return .invalid }
        let exprText = String(src[src.index(after: i)...]).trimmingCharacters(in: .whitespaces)
        guard !exprText.isEmpty else { return .invalid }
        let hasDot = numberText.contains(".")
        let hasComma = numberText.contains(",")
        guard !(hasDot && hasComma) else { return .invalid }
        let parseText = hasComma
            ? numberText.replacingOccurrences(of: ",", with: "")
            : numberText
        guard let number = Double(parseText),
              number.isFinite, number > 0 else { return .invalid }
        return .linear(factor: number, expr: exprText)
    }

    // MARK: Dependency classification

    /// The custom unit names a linear definition references (the
    /// expression atoms that are NOT built-in).
    static func customDeps(of kind: DefKind, in rows: [UserUnitDefinition],
                           active: Set<String>) -> Set<String> {
        guard case .linear(_, let exprText) = kind else { return [] }
        let tokens = exprText.lowercased()
            .split(whereSeparator: { $0 == " " || $0 == "/" || $0 == "*" || $0 == "^" })
            .map(String.init)
        var deps: Set<String> = []
        let rowNames = Set(rows.map { normName($0.name) })
        for t in tokens {
            let n = UnitCatalog.normalize(t)
            if rowNames.contains(n), !active.contains(n) {
                deps.insert(n)
            }
        }
        return deps
    }

    /// Classifies a row that could not resolve: a self/cycle
    /// membership inside the still-pending graph is `cycle`; a
    /// reference to a name no row provides (or a name an inactive row
    /// holds) is `unknownDependency`.
    static func classifyPending(deps: Set<String>, active: Set<String>,
                                rows: [UserUnitDefinition]) -> CustomUnitStatus {
        // Row name → its custom deps (rows with a linear definition).
        let rowNames = Set(rows.map { normName($0.name) })
        let nameToDeps: [String: Set<String>] = rows.reduce(into: [:]) { acc, row in
            let n = normName(row.name)
            guard !n.isEmpty else { return }
            if case .linear(_, let exprText) = parseDefinition(row.definition) {
                let tokens = exprText.lowercased()
                    .split(whereSeparator: { $0 == " " || $0 == "/" || $0 == "*" || $0 == "^" })
                    .map(String.init)
                let d = Set(tokens.map { UnitCatalog.normalize($0) }.filter {
                    rowNames.contains($0) && !active.contains($0)
                })
                if !d.isEmpty { acc[n] = d }
            }
        }
        // A cycle: a walk from a row's deps that returns to the row.
        func isCycleMember(_ start: String) -> Bool {
            var stack = Array(nameToDeps[start] ?? [])
            var seen: Set<String> = []
            while let cur = stack.popLast() {
                if cur == start { return true }
                guard seen.insert(cur).inserted else { continue }
                stack.append(contentsOf: nameToDeps[cur] ?? [])
            }
            return false
        }
        for (n, d) in nameToDeps where !d.isEmpty {
            if isCycleMember(n) { return .cycle }
        }
        return .unknownDependency
    }

    /// The input aliases of a custom unit: its normalized name plus
    /// the trailing-`s` plural — unless either shadows a built-in
    /// token or an alias already claimed by an active unit.
    static func aliases(for name: String, ctx: UnitContext) -> [String] {
        let base = UnitCatalog.normalize(name.lowercased())
        guard !base.isEmpty else { return [] }
        var out: [String] = [base]
        // The plural alias, unless a built-in token or label claims it
        // (the row's own name passed the collision checks, so only the
        // plural can collide).
        let plural = base + "s"
        if UnitCatalog.resolveToken(plural) == nil,
           UnitCatalog.resolveLabel(plural) == nil {
            out.append(plural)
        }
        return out
    }
}
