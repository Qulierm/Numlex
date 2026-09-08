import Foundation

// MARK: - R84: per-evaluation unit context
//
// `UnitContext` is the ONE immutable unit registry an evaluation pass
// uses: the built-in `UnitCatalog` plus the resolved custom units. It is
// assembled ONCE per sheet pass (from the app-global custom-unit rows)
// and threaded explicitly through evaluation, conversion, token
// resolution, syntax highlighting, formatting and settings previews.
// There are NO mutable globals: the built-in catalog stays static, and
// every context is a value. `UnitContext.builtIns` is the zero-custom
// context — byte-for-byte the pre-R84 behavior — and every context-aware
// method falls back to the built-in `UnitCatalog` API, so all existing
// call sites and tests keep their exact semantics.

/// One app-global custom unit row, exactly as the UI represents it: a
/// display NAME plus a DEFINITION source. The resolved form (a linear
/// `UnitExpr`, or a new independent dimension) is DERIVED on every pass
/// — nothing computed is persisted (the store carries name+definition
/// only, inside `AppSettings`, never inside a sheet / `.nlx`).
public struct UserUnitDefinition: Codable, Equatable, Sendable, Identifiable {
    /// Stable identity (survives renames; new-dimension units are keyed
    /// by it).
    public var id: UUID
    /// The display name (input is case-insensitive; auto-pluralized on
    /// input). Bounded length, no digits/operators.
    public var name: String
    /// The definition source: either `<number> <unit…>` (a linear
    /// multiple of existing units) or the literal `new unit` (an
    /// independent dimension).
    public var definition: String

    public init(id: UUID = UUID(), name: String = "", definition: String = "") {
        self.id = id
        self.name = name
        self.definition = definition
    }
}

/// The validation state of ONE custom unit row (drives the settings
/// preview column). `active` rows resolve; everything else is inert —
/// it is simply absent from the context (and, where it collided, the
/// pre-existing built-in/constant keeps working).
public enum CustomUnitStatus: Equatable, Sendable {
    case active
    case empty
    case incomplete
    case invalidName
    case duplicate
    case builtInCollision
    case constantCollision
    case invalidDefinition
    case unknownDependency
    case cycle
    case nonFinite
    case exceedsLimit
}

/// The fully-resolved form of an ACTIVE custom unit row: the name, the
/// definition, and the linear unit it stands for (a new-dimension unit
/// carries its stable axis through the `r84custom<axis>` name tag and a
/// unit vector of zero — its identity lives in the signature's custom
/// axis).
public struct ResolvedCustomUnit: Equatable, Sendable {
    public let id: UUID
    public let name: String            // display name (original case)
    public let definition: String
    /// The resolved linear unit (factor to base, label = the name, or
    /// `r84custom<axis>` for a new dimension).
    public let expr: UnitExpr
    /// The input aliases: the name (normalized) and its trailing-`s`
    /// plural (when it does not shadow anything else).
    public let inputAliases: [String]
    /// The new-dimension axis ordinal (nil for linear-on-existing units).
    public let axis: Int?

    public init(id: UUID, name: String, definition: String,
                expr: UnitExpr, inputAliases: [String], axis: Int?) {
        self.id = id
        self.name = name
        self.definition = definition
        self.expr = expr
        self.inputAliases = inputAliases
        self.axis = axis
    }
}

/// The immutable per-evaluation unit registry.
public struct UnitContext: Sendable {
    /// The resolved, ACTIVE custom units (in row order).
    public let customUnits: [ResolvedCustomUnit]

    /// The zero-custom context: exactly the pre-R84 built-in behavior.
    public static let builtIns = UnitContext(customUnits: [])

    public var hasCustomUnits: Bool { !customUnits.isEmpty }

    // MARK: Context-aware lookups (custom first, built-in fallback)

    /// Resolves ONE unit token (custom aliases first, then the built-in
    /// `UnitCatalog.resolveToken` chain: plural, exponent, prefix, fold).
    public func resolveToken(_ raw: String) -> UnitDef? {
        let t = UnitCatalog.normalize(raw)
        if !t.isEmpty {
            if let u = customExact[t] { return u }
            if let u = customFoldedOnly(t) { return u }
        }
        return UnitCatalog.resolveToken(raw)
    }

    /// Resolves a DISPLAY label to a unit expression (custom labels
    /// first, then built-in labels/expressions).
    public func resolveLabel(_ label: String) -> UnitExpr? {
        let t = UnitCatalog.normalize(label)
        if !t.isEmpty, let e = customLabelExpr[t] { return e }
        if !t.isEmpty, let e = customLabelFoldedOnly(t) { return e }
        return UnitCatalog.resolveLabel(label)
    }

    /// Resolves a full unit EXPRESSION. Single-atom expressions consult
    /// the custom tables first; anything else falls through to the
    /// built-in expression parser (custom units never combine inside a
    /// built-in expression — a custom unit is a single atom).
    public func resolveExpression(_ raw: String) -> UnitCatalog.ParsedExpr? {
        let t = UnitCatalog.normalize(raw)
        if !t.isEmpty, t.count <= 24, !t.contains(" "), !t.contains("/"),
           !t.contains("*"), !t.contains("^"), !t.contains("(") {
            if let u = customExact[t] {
                return UnitCatalog.ParsedExpr(unit: self.expr(of: u), def: u, text: t)
            }
            if let u = customFoldedOnly(t) {
                return UnitCatalog.ParsedExpr(unit: self.expr(of: u), def: u, text: t)
            }
            if t.hasSuffix("s"), t.count > 2, let u = customExact[String(t.dropLast())] {
                return UnitCatalog.ParsedExpr(unit: self.expr(of: u), def: u, text: t)
            }
        }
        return UnitCatalog.resolveExpression(raw)
    }

    /// The set of input tokens (normalized) that an active custom unit
    /// claims — used by syntax highlighting and the collision guards.
    public var customInputTokens: Set<String> {
        var s: Set<String> = []
        for c in customUnits { s.formUnion(c.inputAliases) }
        return s
    }

    // MARK: Custom lookup tables (built once per context)

    private let customExact: [String: UnitDef]
    private let customFoldedOwners: [String: [UnitDef]]
    private let customLabelExpr: [String: UnitExpr]
    private let customLabelFoldedOwners: [String: [UnitExpr]]
    /// def ID → the `r84custom<axis>` name tag (new-dimension units):
    /// the axis survives every rebuild of the def's `UnitExpr`.
    private let customAxisTags: [String: String]
    public init(customUnits: [ResolvedCustomUnit]) {
        self.customUnits = customUnits
        var exact: [String: UnitDef] = [:]
        var folded: [String: [UnitDef]] = [:]
        var labels: [String: UnitExpr] = [:]
        var labelFolded: [String: [UnitExpr]] = [:]
        var axisTags: [String: String] = [:]
        for c in customUnits {
            let def = UnitDef(id: c.id.uuidString, kind: c.expr.kind,
                              label: c.expr.label, family: c.expr.family,
                              aliases: c.inputAliases, prefixes: [])
            for a in c.inputAliases where exact[UnitCatalog.normalize(a)] == nil {
                exact[UnitCatalog.normalize(a)] = def
            }
            for a in c.inputAliases {
                let k = UnitCatalog.normalize(a).lowercased()
                if folded[k]?.first(where: { $0.id == def.id }) == nil {
                    folded[k, default: []].append(def)
                }
            }
            let lk = UnitCatalog.normalize(c.expr.label)
            if labels[lk] == nil { labels[lk] = c.expr }
            let lf = lk.lowercased()
            if labelFolded[lf]?.first(where: { $0.label == c.expr.label }) == nil {
                labelFolded[lf, default: []].append(c.expr)
            }
            if let axis = c.axis {
                axisTags[c.id.uuidString] = "r84custom\(axis)"
            }
        }
        self.customExact = exact
        self.customFoldedOwners = folded
        self.customLabelExpr = labels
        self.customLabelFoldedOwners = labelFolded
        self.customAxisTags = axisTags
    }



    private func customFoldedOnly(_ t: String) -> UnitDef? {
        let owners = customFoldedOwners[t.lowercased()] ?? []
        return owners.count == 1 ? owners[0] : nil
    }
    private func customLabelFoldedOnly(_ t: String) -> UnitExpr? {
        let owners = customLabelFoldedOwners[t.lowercased()] ?? []
        return owners.count == 1 ? owners[0] : nil
    }

    /// A `UnitExpr` for a custom `UnitDef` (linear only — custom units
    /// are always linear). New-dimension defs keep their `r84custom`
    /// name tag so the signature's custom axis survives.
    func expr(of u: UnitDef) -> UnitExpr {
        let name = customAxisTags[u.id] ?? u.label
        if let v = u.vector, let f = u.linearFactor {
            return UnitExpr(kind: .factor(v, f), vector: v, family: u.family,
                            toBase: f, label: u.label, name: name)
        }
        return UnitExpr(kind: u.kind, vector: u.vector ?? .zero, family: u.family,
                        toBase: 1, label: u.label, name: name)
    }
}
