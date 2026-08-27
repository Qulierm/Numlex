import Foundation

/// Preference-aware input formatting (r19). One pure pass over the
/// typed document returning the transformed text plus the exact
/// document-wide UTF-16 caret map (monotone, one entry per insertion
/// point, newline boundaries stable). Legacy `NotebookFormatting` keeps
/// its pre-r19 behavior for source compatibility; the editor, import and
/// the one-time store migration go through this type with the user's
/// own `InputPreferences`.
///
/// Stages (per line, in order):
///  1. 1:1 glyph substitutions — `*`→`×`, `` ` ``→`+`, digit-bounded
///     p/m/x/d QuickOperators — never change the core order;
///  2. spacing — the bounded natural pass or the math re-emit, only
///     when pad-operators is ON (OFF preserves the typed whitespace);
///  3. thousand grouping — commas inserted into integer parts of digit
///     runs, only for lines that evaluate to a number/variable/money.
public enum InputFormatting {

    // MARK: - Document pass

    public static func formatDocument(
        _ content: String,
        prefs: InputPreferences,
        rates: Rates = Rates(),
        decimalPlaces: Int = 7
    ) -> (text: String, map: [Int]) {
        let lines = content.components(separatedBy: "\n")
        var outLines = [String]()
        outLines.reserveCapacity(lines.count)
        var docMap = [Int]()
        var oldStart = 0
        var newStart = 0
        // The SAME top-down environment advancement as the legacy
        // pass: a natural assignment records its name for LATER lines.
        var env = TypedEnv()
        for line in lines {
            let len = (line as NSString).length
            if let (text, map) = formatLine(line, prefs: prefs, env: &env, rates: rates, decimalPlaces: decimalPlaces) {
                for p in 0...len { docMap.append(newStart + map[p]) }
                outLines.append(text)
                newStart += (text as NSString).length
            } else {
                for p in 0...len { docMap.append(newStart + p) }
                outLines.append(line)
                newStart += len
            }
            oldStart += len + 1
            newStart += 1
        }
        return (outLines.joined(separator: "\n"), docMap)
    }

    // MARK: - Line pass

    public static func formatLine(
        _ line: String,
        prefs: InputPreferences,
        rates: Rates = Rates(),
        decimalPlaces: Int = 7
    ) -> (text: String, map: [Int])? {
        var env = TypedEnv()
        return formatLine(line, prefs: prefs, env: &env, rates: rates, decimalPlaces: decimalPlaces)
    }

    /// One line under the given prefs; `env` is the shared top-down
    /// typing environment (advanced exactly like the legacy pass).
    /// Returns nil when the line comes back byte-identical.
    static func formatLine(
        _ line: String,
        prefs: InputPreferences,
        env: inout TypedEnv,
        rates: Rates,
        decimalPlaces: Int
    ) -> (text: String, map: [Int])? {
        guard !line.isEmpty else { return nil }
        var kind: PassKind = .none
        var groupable = false
        if NotebookFormatting.isNaturalShape(line, env: env) {
            kind = .natural
            groupable = true
            // Record the assignment for the later lines (legacy parity).
            _ = evalLineTyped(line, env: &env, rates: rates, decimalPlaces: decimalPlaces,
                              now: Date(), calendar: Calendar.current)
        } else if let res = evalLineTyped(line, env: &env, rates: rates, decimalPlaces: decimalPlaces,
                                          now: Date(), calendar: Calendar.current) {
                switch res {
                case .number(let v, _): kind = .math; groupable = v.isFinite
                case .variable: kind = .math; groupable = true
                case .money(let v, _): kind = .money; groupable = v.isFinite
                case .error: kind = .math
                default: break
                }
        }
        guard kind != .none else { return nil }

        // Stage 1: 1:1 glyph substitutions (core order preserved).
        var chars = Array(line.utf16)
        applyGlyphs(&chars, prefs: prefs)
        var text = String(utf16CodeUnits: chars, count: chars.count)
        var map = Array(0...chars.count)

        // Stage 2: spacing, only when the user wants it.
        if prefs.padOperators {
            switch kind {
            case .natural, .money:
                let r = NotebookFormatting.naturalOperatorCanonical(text, replaceStar: prefs.replaceAsterisk)
                if r.text != text { text = r.text; map = r.map }
            case .math, .none:
                let canon = NotebookFormatting.canonicalMathText(text, replaceStar: prefs.replaceAsterisk)
                if canon != text {
                    text = canon
                    map = NotebookFormatting.insertionMap(from: String(line), to: canon)
                }
            }
        }

        // Stage 3: thousand separators on computed lines only. The
        // grouping stage maps ITS input (the text after the spacing
        // pass); compose with the accumulated map when the spacing
        // pass moved anything.
        if prefs.groupNumbers && groupable, let (grouped, gmap) = groupDigits(Array(text.utf16)) {
            text = String(utf16CodeUnits: grouped, count: grouped.count)
            if prefs.padOperators {
                map = map.indices.map { gmap[map[$0]] }
            } else {
                map = gmap
            }
        }

        guard text != line else { return nil }
        return (text, map)
    }

    private enum PassKind { case none, natural, math, money }

    // MARK: - Stage 1: glyph substitutions (1:1)

    static func applyGlyphs(_ c: inout [unichar], prefs: InputPreferences) {
        if prefs.replaceAsterisk {
            for i in c.indices where c[i] == 0x2A { c[i] = 0x00D7 }  // * -> ×
        }
        if prefs.replaceBacktick {
            for i in c.indices where c[i] == 0x60 { c[i] = 0x2B }    // ` -> +
        }
        if prefs.quickOperators {
            for i in c.indices {
                let ch = c[i]
                guard ch == 0x70 || ch == 0x6D || ch == 0x78 || ch == 0x64 else { continue }
                guard i > 0, i + 1 < c.count else { continue }
                let l = c[i - 1], r = c[i + 1]
                guard l >= 0x30, l <= 0x39, r >= 0x30, r <= 0x39 else { continue }
                // Digit-bounded completion: the left digit must not be
                // part of an identifier (`a5m3`, `x12p4y` stay
                // untouched) — walk left across the whole digit run.
                var d = i - 1
                while d >= 0, isDigit16(c[d]) { d -= 1 }
                if d >= 0, isIdentChar16(c[d]) { continue }
                switch ch {
                case 0x70: c[i] = 0x2B     // p -> +
                case 0x6D: c[i] = 0x2D     // m -> -
                case 0x78: c[i] = 0x00D7   // x -> ×
                case 0x64: c[i] = 0x00F7   // d -> ÷
                default: break
                }
            }
        }
    }

    static func isDigit16(_ u: unichar) -> Bool { u >= 0x30 && u <= 0x39 }
    static func isIdentChar16(_ u: unichar) -> Bool {
        (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A) || u == 0x5F
    }

    // MARK: - Stage 3: thousand grouping

    /// Groups the integer parts of digit runs with commas and returns
    /// the line map for the WHOLE grouping stage (pre-grouping line
    /// positions -> grouped line positions). Returns nil when nothing
    /// changes.
    ///
    /// Skipped: identifier tails (`x1234`), fractional parts (a run
    /// right after `.`), exponent digits (a run right after `e`/`E`),
    /// runs shorter than four integer digits. In-progress grouped
    /// tokens are merged and regrouped, so `1,0000` normalizes to
    /// `10,000`; a digit run after a comma whose merge is ambiguous
    /// stays byte-identical.
    static func groupDigits(_ c: [unichar]) -> (chars: [unichar], map: [Int])? {
        let n = c.count
        // Detect the edit regions: each replaces a pre range with a
        // regrouped digit string (same digits, new comma placement).
        struct Edit { var start: Int; var end: Int; var post: [unichar] }
        var edits: [Edit] = []
        var i = 0
        while i < n {
            if !isDigit16(c[i]) { i += 1; continue }
            let a = i
            while i < n, isDigit16(c[i]) { i += 1 }
            let b = i
            let prev = a > 0 ? c[a - 1] : 0
            // Identifier/exponent/fraction guards apply to the run itself.
            if isIdentChar16(prev) || prev == 0x65 || prev == 0x45 || prev == 0x2E { continue }
            // Merge a preceding grouped prefix when well-formed
            // (`1,0000` in progress). An invalid merge leaves the run
            /// untouched (it belongs to an ambiguous group).
            var sStart = a
            if prev == 0x2C {
                var k = a - 1
                while k > 0, isDigit16(c[k - 1]) || c[k - 1] == 0x2C { k -= 1 }
                if k < a - 1, isDigit16(c[k]) {
                    var valid = true
                    var j = k
                    while j < b {
                        if c[j] == 0x2C {
                            // Digits on both sides; at most four after
                            // (three + the one in progress).
                            guard isDigit16(c[j - 1]), isDigit16(c[j + 1]) else { valid = false; break }
                            var after = 0
                            var t = j + 1
                            while t < b, isDigit16(c[t]) { after += 1; t += 1 }
                            if after > 4 { valid = false; break }
                        }
                        j += 1
                    }
                    let before = k > 0 ? c[k - 1] : 0
                    if valid, !isIdentChar16(before), before != 0x2E, before != 0x65, before != 0x45 {
                        sStart = k
                    } else {
                        continue  // ambiguous: leave the run byte-identical
                    }
                } else {
                    continue
                }
            }
            let seg = Array(c[sStart..<b])
            let digitsOnly = seg.filter { isDigit16($0) }
            let intLen = digitsOnly.count
            guard intLen >= 4 else { continue }
            var post = [unichar]()
            post.reserveCapacity(intLen + intLen / 3)
            var written = 0
            for d in digitsOnly {
                post.append(d)
                written += 1
                if written < intLen, (intLen - written) % 3 == 0 { post.append(0x2C) }
            }
            if post.count != seg.count || post != seg {
                edits.append(Edit(start: sStart, end: b, post: post))
            }
        }
        guard !edits.isEmpty else { return nil }
        // Build the grouped line + the exact map (pre positions 0...n).
        var out = [unichar]()
        out.reserveCapacity(n + 8)
        var map = [Int](repeating: 0, count: n + 1)
        var pre = 0
        var postPos = 0
        var ei = 0
        while pre <= n {
            if ei < edits.count, edits[ei].start == pre {
                let e = edits[ei]
                let segPre = Array(c[e.start..<e.end])
                let digitCount = e.post.filter { isDigit16($0) }.count
                // qEnd[k] = the offset in `post` after the k-th digit,
                // including any commas placed right after it.
                var qEnd = [Int](repeating: 0, count: digitCount + 1)
                var k = 0
                var p = 0
                for ch in e.post {
                    if isDigit16(ch) {
                        k += 1
                        p += 1
                        qEnd[k] = p
                    } else {
                        p += 1
                        if k > 0 { qEnd[k] = p }
                    }
                }
                for t in 0...segPre.count {
                    var kk = 0
                    for ch in segPre.prefix(t) where isDigit16(ch) { kk += 1 }
                    map[e.start + t] = postPos + qEnd[kk]
                }
                out.append(contentsOf: e.post)
                postPos += e.post.count
                pre = e.end
                ei += 1
            } else if pre < n {
                map[pre] = postPos
                out.append(c[pre])
                postPos += 1
                pre += 1
            } else {
                map[pre] = postPos
                break
            }
        }
        return (out, map)
    }
}
