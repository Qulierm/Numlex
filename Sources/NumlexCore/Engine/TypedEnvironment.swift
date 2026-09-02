import Foundation

/// One quantity a named value can carry. Unitless scalars keep the
/// legacy variable semantics; money carries its ISO fiat code so later
/// lines preserve the currency.
public enum TypedQty: Equatable, Sendable {
    case scalar(Double)
    case money(Double, code: String)
}

/// Canonical name key: casefolded, whitespace-collapsed. `Monthly Rent`
/// and `monthly   rent` address the same name.
public func canonicalNameKey(_ display: String) -> String {
    display.split(whereSeparator: { $0.isWhitespace })
        .joined(separator: " ")
        .lowercased()
}

/// The top-down typed evaluation environment shared by sheet
/// evaluation, reference tokens, the syntax classifier, the notebook
/// formatter and auto-titling. There is NO global state and no
/// persistence sidecar: every evaluation pass re-derives the values
/// deterministically from the sheet text (plus optional seed values for
/// backward-compatible `[String: Double]` callers).
public struct TypedEnv: Equatable {
    public struct Entry: Equatable {
        public let display: String
        public let qty: TypedQty
        /// True for global user constants (r33): IMMUTABLE — every
        /// assignment route guards on this and returns
        /// `Cannot assign to constant` instead of shadowing or mutating.
        public var isConstant: Bool = false
    }

    private var byKey: [String: Entry]
    private var order: [String]

    public init(seed: [String: Double] = [:]) {
        byKey = [:]
        order = []
        for (k, v) in seed where v.isFinite {
            set(display: k, qty: .scalar(v))
        }
    }

    /// Declaration-order entries (top-down).
    public var entries: [Entry] { order.map { byKey[$0]! } }

    /// Every declared display name.
    public var names: [String] { order.map { byKey[$0]!.display } }

    public subscript(key: String) -> Entry? { byKey[key] }

    public func entry(display: String) -> Entry? {
        byKey[canonicalNameKey(display)]
    }

    public mutating func set(display: String, qty: TypedQty) {
        let k = canonicalNameKey(display)
        if byKey[k] == nil { order.append(k) }
        // A plain set never demotes an immutable constant (the
        // assignment guards make this path unreachable; the flag is
        // the safety net that keeps it so).
        let isConstant = byKey[k]?.isConstant ?? false
        byKey[k] = Entry(display: display, qty: qty, isConstant: isConstant)
    }

    /// Records an IMMUTABLE global constant (r33). A later plain
    /// `set` under the same canonical name keeps the constant flag —
    /// the assignment guards make that path unreachable, and the flag
    /// is the safety net that makes it so.
    public mutating func setConstant(display: String, qty: TypedQty) {
        let k = canonicalNameKey(display)
        if byKey[k] == nil { order.append(k) }
        byKey[k] = Entry(display: display, qty: qty, isConstant: true)
    }

    /// Whether a display name is an active global constant (case/
    /// whitespace-insensitive). Used by EVERY assignment route.
    public func isConstant(display: String) -> Bool {
        byKey[canonicalNameKey(display)]?.isConstant == true
    }

    /// Scalar projection for the legacy `[String: Double]` plumbing.
    public func scalarDict() -> [String: Double] {
        var d: [String: Double] = [:]
        for e in entries {
            if case .scalar(let v) = e.qty, v.isFinite { d[e.display] = v }
        }
        return d
    }

    /// Whether a display name is a legacy single ASCII identifier
    /// (`[A-Za-z_]\w*`). Multiword names (and anything non-ASCII) are
    /// compound: only the shared typed pipeline can reference them.
    public static func isLegacyIdentifier(_ s: String) -> Bool {
        guard let first = s.first else { return false }
        guard (first.isLetter && first.isASCII) || first == "_" else { return false }
        return s.allSatisfy {
            ($0.isLetter || $0.isNumber) && $0.isASCII || $0 == "_"
        }
    }

    /// Names the legacy single-identifier parser cannot reference.
    public var compoundNames: [Entry] {
        entries.filter { !Self.isLegacyIdentifier($0.display) }
    }
}

// MARK: - Named-value reference matching

/// Longest-boundary matching of DECLARED names inside a line. The same
/// pure matcher feeds the evaluator (placeholder substitution) and the
/// syntax classifier (green spans), so the two can never diverge.
///
/// Rules:
/// - names match case-insensitively with flexible inner whitespace;
/// - a name starts only at a word boundary (no letter/digit before);
/// - a name ends at the end of a maximal word (so `rent` never matches
///   inside `renter`), and at each position the LONGEST matching name
///   wins (so `rent` never steals `monthly rent`);
/// - matches are non-overlapping, left to right.
public enum NamedValues {
    public struct Match: Equatable {
        public let display: String
        public let range: NSRange
        public let entry: TypedEnv.Entry
    }

    private struct Name {
        let display: String
        let words: [String]
        let entry: TypedEnv.Entry
    }

    /// Every declared-name occurrence in `line`, or empty when no
    /// declared name appears.
    public static func matches(in line: String, env: TypedEnv) -> [Match] {
        let names: [Name] = env.entries.map {
            Name(display: $0.display,
                 words: $0.display.split(whereSeparator: { $0.isWhitespace })
                     .map { $0.lowercased() },
                 entry: $0)
        }
        guard !names.isEmpty else { return [] }
        let ns = line as NSString
        let len = ns.length
        var result: [Match] = []
        var pos = 0
        while pos < len {
            let c = ns.character(at: pos)
            guard isAsciiLetter16(c) else { pos += 1; continue }
            if pos > 0, isAlnum16(ns.character(at: pos - 1)) {
                pos += 1
                continue
            }
            var best: (range: NSRange, entry: TypedEnv.Entry)?
            for name in names {
                var p = pos
                var ok = true
                for w in name.words {
                    while p < len && (ns.character(at: p) == 0x20 || ns.character(at: p) == 0x09) {
                        p += 1
                    }
                    guard p < len else { ok = false; break }
                    var q = p
                    while q < len, isWordChar16(ns.character(at: q)) { q += 1 }
                    if ns.substring(with: NSRange(location: p, length: q - p)).lowercased() != w {
                        ok = false
                        break
                    }
                    p = q
                }
                guard ok, p > pos else { continue }
                let r = NSRange(location: pos, length: p - pos)
                if best == nil || r.length > best!.range.length {
                    best = (r, name.entry)
                }
            }
            if let b = best {
                // r47: a recognized BUILTIN call head is grammar, never
                // a name reference: when a variable or constant is named
                // `sum`, the call `sum(...)` must not be substituted —
                // the builtin wins at the call head and the argument
                // list stays matchable by the names it contains.
                let end = b.range.location + b.range.length
                if MathFunctions.isKnown(b.entry.display.lowercased()) {
                    var k = end
                    while k < len, ns.character(at: k) == 0x20 || ns.character(at: k) == 0x09 {
                        k += 1
                    }
                    if k < len, ns.character(at: k) == 0x28 {
                        pos += 1
                        continue
                    }
                }
                result.append(Match(display: displayName(for: b.entry, in: line, range: b.range),
                                    range: b.range, entry: b.entry))
                pos = end
            } else {
                pos += 1
            }
        }
        return result
    }

    /// The name's stored display (the canonical identifier); matching
    /// is case/whitespace-insensitive but the KEY is the display name.
    private static func displayName(for entry: TypedEnv.Entry,
                                    in line: String, range: NSRange) -> String {
        entry.display
    }

    /// Whether the line references at least one declared COMPOUND
    /// (non-single-identifier) name — kept for classification and
    /// declared-name detection.
    public static func referencesCompoundName(_ line: String, env: TypedEnv) -> Bool {
        guard !env.compoundNames.isEmpty else { return false }
        return matches(in: line, env: env).contains {
            !TypedEnv.isLegacyIdentifier($0.display)
        }
    }

    /// The pipeline activation rule: a declared compound name anywhere
    /// in the line, a declared MONEY name used in an expression (the
    /// line carries an operator or a digit — plain prose mentioning a
    /// money name stays prose), or ANY global constant (r33) —
    /// constants always take the typed pipeline so a single-identifier
    /// constant matches case/whitespace-insensitively and evaluates
    /// strictly. Ordinary single unitless variables keep the legacy
    /// free-expression path untouched.
    public static func referencesTypedName(_ line: String, env: TypedEnv) -> Bool {
        guard !env.entries.isEmpty else { return false }
        let expressionLike = line.unicodeScalars.contains {
            ("0123456789+-*/^%(".unicodeScalars.contains($0))
                || $0 == "×" || $0 == "÷"
        }
        return matches(in: line, env: env).contains { m in
            if m.entry.isConstant { return true }
            if !TypedEnv.isLegacyIdentifier(m.display) { return true }
            if case .money = m.entry.qty { return expressionLike }
            return false
        }
    }
}

private func isAsciiLetter16(_ c: UInt16) -> Bool {
    (0x41...0x5A).contains(c) || (0x61...0x7A).contains(c)
}

private func isAlnum16(_ c: UInt16) -> Bool {
    isAsciiLetter16(c) || (0x30...0x39).contains(c)
}

private func isWordChar16(_ c: UInt16) -> Bool {
    isAlnum16(c) || c == 0x5F
}

/// Placeholder identifier for one substituted name: a Cyrillic letter
/// (a legal tokenizer identifier) that is not a legal English name and
/// cannot appear in user prose. `placeholder(0)` = U+0400 followed by
/// `0`.
public func namePlaceholder(_ index: Int) -> String {
    "\u{0400}" + String(index)
}
