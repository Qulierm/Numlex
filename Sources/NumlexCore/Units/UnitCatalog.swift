import Foundation

/// A measurement unit definition: its finite-transform kind, canonical
/// output label, disambiguation family, input aliases and (for linear
/// units) which SI prefixes may attach to it.
///
/// Aliases are matched after `UnitCatalog.normalize`; case is
/// PRESERVED in the tables (so `MB` bytes and `Mb` bits coexist) — a
/// case-folded fallback is applied only when it resolves to a SINGLE
/// unit, so `mb` (ambiguous between `MB` and `Mb`) is a known unit
/// neither: it is an unknown unit, deterministically.
public struct UnitDef: Hashable, Sendable {
    public let id: String
    public let kind: UnitKind
    public let label: String
    public let family: UnitFamily
    /// Input aliases (raw; normalization happens at lookup). The label
    /// itself is always accepted as an input alias too.
    public let aliases: [String]
    /// Prefixes this atom may take (`"k"`, `"M"`, ...); empty = none.
    public let prefixes: [String]

    public init(id: String,
                kind: UnitKind,
                label: String,
                family: UnitFamily = .none,
                aliases: [String] = [],
                prefixes: [String] = []) {
        self.id = id
        self.kind = kind
        self.label = label
        self.family = family
        self.aliases = aliases
        self.prefixes = prefixes
    }

    public var vector: DimensionVector? {
        if case .factor(let v, _) = kind { return v }
        return nil
    }

    /// The exact linear factor of a `.factor` unit (base units per one).
    public var linearFactor: Double? {
        if case .factor(_, let f) = kind { return f }
        return nil
    }
}

/// The result of parsing a unit expression: either one special unit
/// (temperature/currency/fuel) or a linear combination with a combined
/// dimension vector, factor and family. `label` is the canonical pretty
/// output (the string a conversion result is reported in).
public struct UnitExpr: Hashable, Sendable {
    public let kind: UnitKind
    public let vector: DimensionVector
    public let family: UnitFamily
    /// value → base units (linear only; always finite for finite input).
    public let toBase: Double
    /// base units → value (linear only; `fromBase = b / toBase`).
    public let label: String
    /// Normalized expression text (for equality/diagnostics).
    public let name: String

    public var isLinear: Bool {
        if case .factor = kind { return true }
        return false
    }
}

public enum UnitCatalog {

    // MARK: - Normalization

    /// Unicode-normalizes a unit token/expression for lookup:
    /// micro signs (µ U+00B5 / μ U+03BC) unify to `µ`, middle dots and
    /// times signs become `*`, division slash becomes `/`, superscript
    /// exponents become `^2`/`^3`, and whitespace collapses to single
    /// spaces. Case is NEVER changed here (case-sensitive data units).
    public static func normalize(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "\u{00B5}", "\u{03BC}": out.append("µ")
            case "\u{00B7}", "\u{00D7}": out.append("*")
            case "\u{00F7}": out.append("/")
            case "\u{00B2}": out.append("^2")
            case "\u{00B3}": out.append("^3")
            default: out.append(ch)
            }
        }
        var collapsed = ""
        var lastWasSpace = true
        for ch in out {
            if ch == " " || ch == "\t" {
                if !lastWasSpace && !collapsed.isEmpty { collapsed.append(" ") }
                lastWasSpace = true
            } else {
                collapsed.append(ch)
                lastWasSpace = false
            }
        }
        // A trailing period from `in.`-style input is not part of a unit.
        if collapsed.hasSuffix("."), collapsed.count > 1 {
            collapsed.removeLast()
        }
        // Tighten spaces around expression operators so the canonical
        // spacing (`km / L`, `L / 100km`) resolves like the compact form.
        var tight = ""
        for ch in collapsed {
            if ch == " " {
                if let last = tight.last, last == "/" || last == "*" || last == "^" {
                    continue
                }
                tight.append(ch)
            } else if ch == "/" || ch == "*" || ch == "^" {
                if let last = tight.last, last == " " {
                    tight.removeLast()
                }
                tight.append(ch)
            } else {
                tight.append(ch)
            }
        }
        return trimmed(tight)
    }

    private static func trimmed(_ s: String) -> String {
        var a = s.startIndex, b = s.endIndex
        while a < b, s[a] == " " { a = s.index(after: a) }
        while b > a {
            let prev = s.index(before: b)
            if s[prev] == " " { b = prev } else { break }
        }
        return String(s[a..<b])
    }

    // MARK: - Tables (built once from `catalog`)

    private static let catalog: [UnitDef] = allUnits

    /// INPUT alias table (aliases ONLY — labels are a separate space,
    /// consulted as a last-resort fallback in `resolveToken`). This is
    /// what lets `C` mean celsius (alias) while the coulomb's label is
    /// also `C`.
    private static let byExact: [String: UnitDef] = {
        var m: [String: UnitDef] = [:]
        for u in catalog {
            for a in u.aliases where m[normalize(a)] == nil {
                m[normalize(a)] = u
            }
        }
        return m
    }()

    /// Case-folded owners, in registration order (used ONLY when the
    /// folded form has exactly one owner).
    private static let byFolded: [String: [UnitDef]] = {
        var m: [String: [UnitDef]] = [:]
        for u in catalog {
            for a in u.aliases {
                let key = normalize(a).lowercased()
                if m[key]?.first(where: { $0.id == u.id }) == nil {
                    m[key, default: []].append(u)
                }
            }
        }
        return m
    }()

    /// Full-expression aliases (multi-word and slash forms such as
    /// `nautical mile`, `L/100km`, `N·m`) keyed by normalized text.
    private static let byExactExpr: [String: UnitDef] = {
        var m: [String: UnitDef] = [:]
        for u in catalog {
            for a in u.aliases where a.contains(" ") || a.contains("/") || a.contains("*") {
                m[normalize(a)] = u
            }
        }
        return m
    }()

    private static let byFoldedExpr: [String: [UnitDef]] = {
        var m: [String: [UnitDef]] = [:]
        for u in catalog {
            for a in u.aliases where a.contains(" ") || a.contains("/") || a.contains("*") {
                let key = normalize(a).lowercased()
                if m[key]?.first(where: { $0.id == u.id }) == nil {
                    m[key, default: []].append(u)
                }
            }
        }
        return m
    }()

    /// Label → unit index (used by quantity helpers to resolve the
    /// display labels carried by results and tokens). Labels follow the
    /// same unique-fold rule.
    private static let byLabel: [String: UnitDef] = {
        var m: [String: UnitDef] = [:]
        for u in catalog where m[normalize(u.label)] == nil {
            m[normalize(u.label)] = u
        }
        return m
    }()
    private static let byFoldedLabel: [String: [UnitDef]] = {
        var m: [String: [UnitDef]] = [:]
        for u in catalog {
            let key = normalize(u.label).lowercased()
            if m[key]?.first(where: { $0.id == u.id }) == nil {
                m[key, default: []].append(u)
            }
        }
        return m
    }()

    private static let prefixFactor: [String: Double] = [
        "p": 1e-12, "n": 1e-9, "µ": 1e-6, "m": 1e-3, "c": 1e-2,
        "d": 1e-1, "k": 1e3, "K": 1e3, "M": 1e6, "G": 1e9,
        "T": 1e12, "P": 1e15
    ]

    /// Logarithmic/decibel tokens that must NEVER resolve as a
    /// prefix-decomposed unit (`dB` is a decibel, not deci-byte).
    private static let deniedPrefixTokens: Set<String> = ["dB", "dBm", "dBV", "dBW"]

    // MARK: - Catalog integrity

    /// Alias collisions detected at catalog construction: every
    /// normalized alias claimed by more than one unit. Empty for a
    /// healthy catalog; the test suite asserts this.
    /// Input-alias collisions: every normalized ALIAS claimed by more
    /// than one unit. Empty for a healthy catalog; tests assert this.
    public static func aliasCollisions() -> [String: [String]] {
        var owners: [String: Set<String>] = [:]
        for u in catalog {
            for a in u.aliases {
                owners[normalize(a), default: []].insert(u.id)
            }
        }
        return owners.filter { $0.value.count > 1 }.mapValues { $0.sorted() }
    }

    /// Display-label collisions: two units must never share a label
    /// (labels feed result text and token resolution).
    public static func labelCollisions() -> [String: [String]] {
        var owners: [String: Set<String>] = [:]
        for u in catalog {
            owners[normalize(u.label), default: []].insert(u.id)
        }
        return owners.filter { $0.value.count > 1 }.mapValues { $0.sorted() }
    }

    public static var unitCount: Int { catalog.count }

    /// Every unit definition (stable registration order).
    public static var all: [UnitDef] { catalog }

    // MARK: - Single-token lookup

    /// Resolves ONE normalized unit token through the rule chain:
    /// exact alias → trailing-s plural → exponent (²/³ or trailing 2/3)
    /// → SI prefix decomposition → unique case-folded retry.
    public static func resolveToken(_ raw: String) -> UnitDef? {
        let t = normalize(raw)
        guard !t.isEmpty, t.count <= 24, !deniedPrefixTokens.contains(t) else { return nil }
        if let u = byExact[t] { return u }
        // Plural: trailing `s` (deterministic, documented).
        if t.hasSuffix("s"), t.count > 2, let u = byExact[String(t.dropLast())] { return u }
        // Exponent: ²/³ are normalized to ^2/^3 already, so a GLUED
        // exponent only appears as trailing "2"/"3" on a letter token.
        if let (base, power) = splitTrailingExponent(t) {
            if let b = resolveAtomOnly(base), b.family == .none,
               let f = b.linearFactor, f > 0 {
                let p = Double(power)
                let pf = pow(f, p)
                guard pf.isFinite, pf > 0 else { return nil }
                let v = b.vector!.powered(power)
                return UnitDef(id: "\(b.id)^\(power)",
                               kind: .factor(v, pf),
                               label: powerLabel(b.label, power),
                               family: .none,
                               aliases: [])
            }
        }
        // SI prefix: first char a declared prefix + exact alias atom
        // that allows that prefix.
        if t.count >= 2 {
            let pc = String(t[t.startIndex])
            if let pf = prefixFactor[pc], let base = prefixAtom(String(t.dropFirst()), pc) {
                let factor = (base.linearFactor ?? 0) * pf
                guard factor.isFinite, factor > 0 else { return nil }
                let v = base.vector ?? .zero
                return UnitDef(id: "\(pc)\(base.id)",
                               kind: .factor(v, factor),
                               label: pc + base.label,
                               family: base.family,
                               aliases: [])
            }
        }
        // Unique case-folded retry.
        let f = t.lowercased()
        if let owners = byFolded[f], owners.count == 1 { return owners[0] }
        // Last resort: the unit's own display label (lets results stay
        /// re-typable: `g₀`, `ft·lbf` labels resolve on input too).
        if let u = byLabel[t] { return u }
        if let owners = byFoldedLabel[f], owners.count == 1 { return owners[0] }
        return nil
    }

    /// EXACT-alias lookup of `rest` for an atom that allows `prefix`
    /// (no recursion: `mn` is not milli-nano, `nm` is the nanometer
    /// alias or exact atom only).
    private static func prefixAtom(_ rest: String, _ prefix: String) -> UnitDef? {
        guard let u = byExact[normalize(rest)], u.prefixes.contains(prefix) else { return nil }
        return u
    }

    /// Atom lookup for the base of a trailing exponent: exact alias,
    /// plural, unique fold, and ONE level of SI prefix (`cm3` = (cm)³,
    /// `km2` = (km)²) — but never an exponent of an exponent.
    private static func resolveAtomOnly(_ t: String) -> UnitDef? {
        if let u = byExact[t] { return u }
        if t.hasSuffix("s"), t.count > 2, let u = byExact[String(t.dropLast())] { return u }
        let f = t.lowercased()
        if let owners = byFolded[f], owners.count == 1 { return owners[0] }
        if t.count >= 2, let pc = t.first.map(String.init),
           let pf = prefixFactor[pc], let base = prefixAtom(String(t.dropFirst()), pc) {
            let factor = (base.linearFactor ?? 0) * pf
            guard factor.isFinite, factor > 0 else { return nil }
            return UnitDef(id: "\(pc)\(base.id)",
                           kind: .factor(base.vector ?? .zero, factor),
                           label: pc + base.label,
                           family: base.family,
                           aliases: [])
        }
        return nil
    }

    private static func splitTrailingExponent(_ t: String) -> (String, Int)? {
        guard t.count >= 3 else { return nil }
        let last = t[t.index(before: t.endIndex)]
        guard last == "2" || last == "3" else { return nil }
        // The base must start with a letter (avoids treating "12" as
        // "1"² — bare numbers are not unit bases).
        let base = String(t.dropLast())
        guard base.first?.isLetter == true, let power = Int(String(last)) else { return nil }
        return (base, power)
    }

    private static func powerLabel(_ base: String, _ n: Int) -> String {
        n == 2 ? base + "²" : base + "³"
    }

    /// Resolves a DISPLAY label (result unit text) back to its unit.
    /// Compound labels (`km/h`, `ft²`, `kg/m³`) resolve through the
    /// expression parser.
    public static func resolveLabel(_ label: String) -> UnitExpr? {
        let t = normalize(label)
        guard !t.isEmpty else { return nil }
        if let u = byLabel[t] { return expr(of: u) }
        let f = t.lowercased()
        if let owners = byFoldedLabel[f], owners.count == 1 { return expr(of: owners[0]) }
        if let e = resolveExpression(label) { return e.unit }
        return nil
    }

    static func expr(of u: UnitDef) -> UnitExpr {
        if let v = u.vector, let f = u.linearFactor {
            return UnitExpr(kind: .factor(v, f), vector: v, family: u.family,
                            toBase: f, label: u.label, name: u.label)
        }
        return UnitExpr(kind: u.kind, vector: u.vector ?? .zero, family: u.family,
                        toBase: 1, label: u.label, name: u.label)
    }

    // MARK: - Expression parsing

    /// Parses a full unit expression (bounded): one atom (single token
    /// or full-expression alias), optionally with `^2`/`^3`, optionally
    /// combined with `*`/`/` and bounded parentheses. Returns nil for
    /// anything malformed, unbounded, or mixing special kinds inside
    /// compound algebra (temperature/currency/fuel are standalone only).
    public static func resolveExpression(_ raw: String) -> ParsedExpr? {
        let text = normalize(raw)
        guard !text.isEmpty, text.count <= 40 else { return nil }
        var scanner = Scanner(text: text)
        guard let e = scanner.parseExpr(depth: 0), scanner.atEnd else { return nil }
        return e
    }

    /// A fully parsed linear (or special) unit expression.
    public struct ParsedExpr: Equatable {
        public let unit: UnitExpr
        public let def: UnitDef?          // non-nil for single-atom results
        public let text: String

        public var isSpecial: Bool { !unit.isLinear }
    }

    /// Recursive-descent scanner over the normalized expression text.
    private struct Scanner {
        let text: String
        var pos: String.Index

        init(text: String) {
            self.text = text
            self.pos = text.startIndex
        }

        var atEnd: Bool { pos == text.endIndex }

        mutating func skipSpaces() {
            while pos < text.endIndex, text[pos] == " " { pos = text.index(after: pos) }
        }

        mutating func peek() -> Character? {
            skipSpaces()
            return pos < text.endIndex ? text[pos] : nil
        }

        /// Longest full-expression alias match at the current position
        /// (handles `nautical mile`, `L/100km`, `N·m` aliases, ...),
        /// including the trailing-s plural (`nautical miles`).
        mutating func matchFullAlias() -> UnitDef? {
            skipSpaces()
            // Try the longest suffix first (bounded length). Full aliases
            // and display labels both match here, so re-typed labels
            // (`L/100km`, `US mpg`, `N·m`, `g0`) work as input.
            for len in stride(from: min(40, text.distance(from: pos, to: text.endIndex)),
                              through: 2, by: -1) {
                let end = text.index(pos, offsetBy: len)
                let piece = String(text[pos..<end])
                let norm = normalize(piece)
                // Aliases match with boundary/plural semantics; LABELS
                // only as an exact remainder ("rads" must stay the
                // absorbed-dose alias, never "rad" + plural over the
                // radian LABEL).
                let label = end == text.endIndex ? UnitCatalog.byLabel[norm] : nil
                guard let u = UnitCatalog.byExactExpr[norm] ?? label else { continue }
                if end == text.endIndex {
                    pos = end
                    return u
                }
                let c = text[end]
                if isBoundary(c) {
                    pos = end
                    return u
                }
                // Plural: alias + bare `s` + boundary
                // (`nautical miles` → nautical mile).
                if c == "s" {
                    let sEnd = text.index(after: end)
                    if sEnd == text.endIndex || isBoundary(text[sEnd]) {
                        pos = sEnd
                        return u
                    }
                }
            }
            return nil
        }

        private func isBoundary(_ c: Character) -> Bool {
            c == " " || c == "/" || c == "*" || c == "^" || c == "(" || c == ")"
        }

        mutating func readAtomToken() -> String? {
            skipSpaces()
            guard pos < text.endIndex else { return nil }
            let first = text[pos]
            guard isAtomChar(first) else { return nil }
            var i = pos
            while i < text.endIndex, isAtomChar(text[i]) { i = text.index(after: i) }
            let tok = String(text[pos..<i])
            pos = i
            return tok
        }

        private func isAtomChar(_ c: Character) -> Bool {
            c.isLetter || c.isNumber || c == "µ" || c == "Ω" || c == "°" || c == "_"
        }

        /// expr := term ( "/" expr )?
        mutating func parseExpr(depth: Int) -> ParsedExpr? {
            guard depth <= 2 else { return nil }
            guard let num = parseTerm(depth: depth) else { return nil }
            skipSpaces()
            if let c = peek(), c == "/" {
                pos = text.index(after: pos)
                guard let den = parseExpr(depth: depth + 1) else { return nil }
                guard let n = linearOf(num), let d = linearOf(den) else { return nil }
                let v = n.vector / d.vector
                let f = n.factor / d.factor
                guard f.isFinite, f > 0 else { return nil }
                // Family propagates from the NUMERATOR (B/s is a data
                // rate, km/h is plain speed; J/s keeps the energy
                // family and never silently becomes watts).
                let label = UnitCatalog.prettyQuotient(num.unit.label, den.unit.label)
                return ParsedExpr(unit: UnitExpr(kind: .factor(v, f), vector: v, family: n.family,
                                                 toBase: f, label: label,
                                                 name: "\(num.unit.name)/\(den.unit.name)"),
                                  def: nil, text: "\(num.text)/\(den.text)")
            }
            return num
        }

        /// term := atom { "*" atom }?
        mutating func parseTerm(depth: Int) -> ParsedExpr? {
            guard var left = tryAtom(depth: depth) else { return nil }
            while let c = peek(), c == "*" {
                pos = text.index(after: pos)
                guard let rhs = tryAtom(depth: depth) else { return nil }
                guard let a = linearOf(left), let b = linearOf(rhs) else { return nil }
                guard compatible(a.family, b.family) else { return nil }
                let v = a.vector * b.vector
                let f = a.factor * b.factor
                guard f.isFinite, f > 0 else { return nil }
                let family = a.family == .none ? b.family : a.family
                let label = UnitCatalog.prettyProduct(a.label, b.label)
                left = ParsedExpr(unit: UnitExpr(kind: .factor(v, f), vector: v, family: family,
                                                 toBase: f, label: label,
                                                 name: "\(a.name)*\(b.name)"),
                                  def: nil, text: "\(left.text)*\(rhs.text)")
            }
            return left
        }

        /// Product family rule: both plain, or one plain and the other
        /// named (the named one wins); two DIFFERENT named families
        /// multiply to an error.
        private func compatible(_ f1: UnitFamily, _ f2: UnitFamily) -> Bool {
            switch (f1, f2) {
            case (.none, _), (_, .none): return true
            case (let a, let b): return a == b
            }
        }

        private struct Linear {
            let vector: DimensionVector
            let factor: Double
            let family: UnitFamily
            let label: String
            let name: String
        }

        private func linearOf(_ e: ParsedExpr) -> Linear? {
            guard e.unit.isLinear else { return nil }
            return Linear(vector: e.unit.vector, factor: e.unit.toBase,
                          family: e.unit.family, label: e.unit.label, name: e.unit.name)
        }

        private mutating func tryAtom(depth: Int) -> ParsedExpr? {
            skipSpaces()
            if let c = peek(), c == "(" {
                pos = text.index(after: pos)
                guard let inner = parseExpr(depth: depth + 1) else { return nil }
                skipSpaces()
                guard let closing = peek(), closing == ")" else { return nil }
                pos = text.index(after: pos)
                return inner
            }
            guard let def = parseAtom() else { return nil }
            // Optional explicit power ^2/^3.
            var power = 1
            skipSpaces()
            if let c = peek(), c == "^" {
                pos = text.index(after: pos)
                skipSpaces()
                guard let p = peek(), p == "2" || p == "3" else { return nil }
                power = Int(String(p))!
                pos = text.index(after: pos)
            }
            // Special kinds are STANDALONE only: no powers, and
            // compound assembly below (linearOf) rejects them.
            if def.isSpecialKind {
                guard power == 1 else { return nil }
                return ParsedExpr(unit: UnitExpr(kind: def.kind, vector: def.vector ?? .zero,
                                                 family: def.family, toBase: 1,
                                                 label: def.label, name: def.label),
                                  def: def, text: def.label)
            }
            guard let (v0, f0, fam) = atomVectorPower(def) else { return nil }
            // Named families (angle, data, torque, ...) are legal for a
            // STANDALONE atom; the family wall is enforced by the product
            // rule (compatible) and the division family propagation.
            let v = v0.powered(power)
            let f = pow(f0, Double(power))
            guard f.isFinite, f > 0 else { return nil }
            let label = power == 1 ? def.label : UnitCatalog.powerLabel(def.label, power)
            return ParsedExpr(unit: UnitExpr(kind: .factor(v, f), vector: v, family: fam,
                                             toBase: f, label: label,
                                             name: power == 1 ? def.label : "\(def.label)^\(power)"),
                              def: nil, text: power == 1 ? def.label : "\(def.label)^\(power)")
        }

        /// One atom: full alias → single token (incl. prefix/exponent
        /// lookup).
        mutating func parseAtom() -> UnitDef? {
            if let u = matchFullAlias() { return u }
            guard let tok = readAtomToken() else { return nil }
            return UnitCatalog.resolveToken(tok)
        }

        func atomVectorPower(_ u: UnitDef) -> (DimensionVector, Double, UnitFamily)? {
            guard let v = u.vector, let f = u.linearFactor, f > 0, f.isFinite else { return nil }
            return (v, f, u.family)
        }
    }

    private static func prettyProduct(_ a: String, _ b: String) -> String {
        a + "·" + b
    }

    private static func prettyQuotient(_ num: String, _ den: String) -> String {
        den.contains("·") ? "\(num)/(\(den))" : "\(num)/\(den)"
    }
}

extension UnitDef {
    /// Whether the unit uses a finite NON-linear transform (temperature,
    /// currency, fuel) — such units are standalone only.
    public var isSpecialKind: Bool {
        switch kind {
        case .factor: return false
        case .temperature, .currency, .fuel: return true
        }
    }
}
