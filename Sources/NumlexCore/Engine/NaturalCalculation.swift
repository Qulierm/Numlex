import Foundation

/// Typed natural-calculation detection for money lines.
///
/// Replaces the old blind word-stripping fallback for currency-looking
/// input: a line that carries a currency marker (a symbol adjacent to a
/// number, or an uppercase ISO code annotating a number) MUST parse as a
/// complete money expression or return a hidden generic error — it can
/// never fall through to a leading-number result.
///
/// Grammar (English natural words only):
/// - currency markers: `CA$` `NZ$` `HK$` `A$` `S$` `$` (→ USD by
///   default), `€` `£` `¥` `₽`, or `<number> <ISO-3 code>`;
/// - amounts: grouping (`$3,400`), decimals, scientific input, and the
///   shared compact suffixes (`$3k`);
/// - one currency per line: a second, different currency is a hidden
///   error (`$10 + €5`);
/// - prose: a BOUNDED neutral word list (`lunch was`, `earnings`,
///   `people`, `tip`, `sales tax`, ...) is dropped; any other word that
///   is not a known variable or the percent infix `of` makes the line
///   malformed;
/// - arithmetic: everything the shared expression engine does — `+`,
///   `-`, `×`, `÷`, contextual percentages, `of`, parentheses — with
///   the ISO code carried through the result.
public enum NaturalCalculation {

    public enum Outcome: Equatable {
        case money(value: Double, code: String)
        case malformed
        case none
    }

    /// Bounded neutral prose words that may surround money amounts.
    static let neutralWords: Set<String> = [
        "was", "is", "lunch", "dinner", "breakfast", "earnings", "income",
        "salary", "people", "person", "tip", "tips", "tax", "taxes",
        "sales", "total", "bill", "order", "cost", "price", "item",
        "items", "each", "spent", "paid", "got", "for", "the",
    ]

    private static let markerRe = try? NSRegularExpression(
        pattern: CurrencyPresentation.inputMarkerPattern)
    private static let wordRe = try? NSRegularExpression(
        pattern: #"(?<![0-9])[A-Za-z_]\w*"#)
    private static let isoAnnotationRe = try? NSRegularExpression(
        pattern: #"(?<=[0-9.])\s+([A-Z]{3})(?![A-Za-z0-9_])"#)

    /// Detects and evaluates a natural money line. `variables` lets known
    /// identifiers stay in the cleaned expression.
    public static func tryMoney(line: String, variables: [String: Double]) -> Outcome {
        guard let markerRe, let wordRe else { return .none }
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)

        // --- Locate currency markers (symbols adjacent to numbers) -----
        var codes: Set<String> = []
        var symbolRanges: [NSRange] = []
        for m in markerRe.matches(in: line, range: full) {
            let after = m.range.location + m.range.length
            let c = after < ns.length ? ns.character(at: after) : 0
            guard c == 0x2E || (0x30...0x39).contains(c) else {
                // A `$` not glued to a number is prose, not money.
                continue
            }
            let marker = ns.substring(with: m.range)
            guard let code = CurrencyPresentation.code(forMarker: marker) else { continue }
            codes.insert(code)
            symbolRanges.append(m.range)
        }

        // --- ISO code annotations: `100 USD` ---------------------------
        if codes.isEmpty, let isoRe = isoAnnotationRe {
            for m in isoRe.matches(in: line, range: full) where m.numberOfRanges >= 2 {
                let code = ns.substring(with: m.range(at: 1))
                guard FiatCurrencies.codes.contains(code) else { continue }
                codes.insert(code)
                break
            }
        }

        guard !codes.isEmpty else { return .none }
        // Assignments own their `=`; money detection never touches them.
        if line.contains("=") { return .none }
        // Two different currencies are never silently combined.
        guard codes.count == 1, let code = codes.first else { return .malformed }

        // --- Clean the expression ---------------------------------------
        var cleaned = line
        // Remove symbol markers (the number stays).
        for r in symbolRanges.sorted(by: { $0.location > $1.location }) {
            cleaned = (cleaned as NSString).replacingCharacters(
                in: r, with: "")
        }
        // Remove ISO annotations (keep the number).
        if symbolRanges.isEmpty, let isoRe = isoAnnotationRe {
            for m in isoRe.matches(in: cleaned, range: (cleaned as NSString)
                .fullRange).reversed() {
                let r = NSRange(location: m.range(at: 1).location,
                                length: m.range(at: 1).length)
                // Swallow the preceding space too.
                let loc = r.location > 0
                    && (cleaned as NSString).character(at: r.location - 1) == 0x20
                    ? r.location - 1 : r.location
                let len = r.length + (loc == r.location ? 0 : 1)
                cleaned = (cleaned as NSString).replacingCharacters(
                    in: NSRange(location: loc, length: len), with: "")
            }
        }

        // Bounded prose stripping: neutral words drop, known variables
        // stay, `of` (the percent infix) stays, anything else malformed.
        let cleanedNS = cleaned as NSString
        var badWord = false
        for m in wordRe.matches(in: cleaned, range: NSRange(location: 0, length: cleanedNS.length))
            .reversed() {
            let word = cleanedNS.substring(with: m.range)
            let lower = word.lowercased()
            if neutralWords.contains(lower) {
                // Drop the word and one adjacent space (if present).
                let loc = m.range.location > 0
                    && cleanedNS.character(at: m.range.location - 1) == 0x20
                    ? m.range.location - 1 : m.range.location
                let len = m.range.length + (loc == m.range.location ? 0 : 1)
                cleaned = (cleaned as NSString).replacingCharacters(
                    in: NSRange(location: loc, length: len), with: "")
            } else if lower == "of" || variables[word] != nil {
                continue
            } else {
                badWord = true
                break
            }
        }
        if badWord { return .malformed }

        let trimmed = cleaned.trimmingCharacters(in: .whitespaces)
        guard trimmed.range(of: #"\d"#, options: .regularExpression) != nil else {
            return .malformed
        }

        // Same engine the free-expression path uses: compact suffixes
        // (`3k`), grouping commas, contextual percentages, `of`, `÷`.
        do {
            let raw = try evaluateExpression(normalizeExprCorrect(trimmed), variables: variables)
            guard raw.isFinite else { return .malformed }
            return .money(value: roundResult(raw, decimalPlaces: 10), code: code)
        } catch {
            return .malformed
        }
    }

    /// Money-aware prose stripping for reference-token lines: the same
    /// bounded neutral-word drop as `tryMoney`, applied only when the
    /// line is money-context (a currency marker, or the token quantity
    /// carrying a currency unit). Returns nil when a non-whitelisted
    /// word would survive (hidden error), or the line when unchanged.
    public static func stripTokenProse(
        line: String,
        variables: [String: Double],
        moneyContext: Bool
    ) -> String? {
        guard moneyContext, let wordRe else { return line }
        let ns = line as NSString
        var hasWord = false
        var hasBadWord = false
        var cleaned = line
        for m in wordRe.matches(in: line, range: NSRange(location: 0, length: ns.length))
            .reversed() {
            let word = ns.substring(with: m.range)
            let lower = word.lowercased()
            if neutralWords.contains(lower) {
                hasWord = true
                let loc = m.range.location > 0
                    && ns.character(at: m.range.location - 1) == 0x20
                    ? m.range.location - 1 : m.range.location
                let len = m.range.length + (loc == m.range.location ? 0 : 1)
                cleaned = (cleaned as NSString).replacingCharacters(
                    in: NSRange(location: loc, length: len), with: "")
            } else if lower == "of" || variables[word] != nil {
                hasWord = true
            } else {
                hasWord = true
                hasBadWord = true
                break
            }
        }
        _ = hasWord
        return hasBadWord ? nil : cleaned
    }

    /// Whether a token line is in money context: a currency marker is
    /// present, or the resolved token quantities carry currency units.
    public static func isMoneyContext(line: String, tokenUnits: [String?]) -> Bool {
        if let markerRe,
           let m = markerRe.firstMatch(in: line,
                                       range: NSRange(location: 0, length: (line as NSString).length)) {
            let after = m.range.location + m.range.length
            if after < (line as NSString).length {
                let c = (line as NSString).character(at: after)
                if c == 0x2E || (0x30...0x39).contains(c) { return true }
            }
        }
        let currencyUnits = tokenUnits.filter { unit in
            unit.map(isCurrencyCode) ?? false
        }
        guard !currencyUnits.isEmpty else { return false }
        return tokenUnits.allSatisfy { unit in
            unit == nil || isCurrencyCode(unit)
        }
    }
}

private extension NSString {
    var fullRange: NSRange { NSRange(location: 0, length: length) }
}
