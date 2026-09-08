//
//  MixedUnitEngine.swift
//  Numlex
//
//  R84: the mixed unit expression engine.
//
//  The language: quantities (`5 m`, `2.5 kg`), plain numbers, named
//  values (unitless scalars and quantities), the operators
//  `+ - * / ^ ( ) × ÷ of`, parentheses, and a `to|in|as <unit>`
//  target suffix. Every line is either fully in this language (a
//  shape hit) or not in it at all — a shape-owned line that fails to
//  parse is a visible error, never a word-strip fallback.
//
//  Strict linear algebra (no display-String identity):
//    - addition/subtraction requires ONE identical dimension
//      signature on both sides, or one side PLAIN (the plain side
//      assimilates the other's unit: `300 + 20 km` = `320 km`).
//    - multiplication/division compose signatures; currency and
//      temperature/other special kinds are rejected.
//    - the display unit of a result is the COARSER operand unit
//      (the one with the larger base factor); ties keep the left.
//
//  A quantity literal is `<number>␣<unit word>`: a GLUED letter is a
//  compact notation (`5m` = 5 million), never a unit.
//

import Foundation

// MARK: - Tokens

/// One token of the mixed-unit language. Every token carries the
/// NSRange (UTF-16) of the source text it consumed — the syntax
/// painter reuses these spans directly.
enum MToken: Equatable {
    /// A plain (unitless) number.
    case number(value: Double, range: NSRange)
    /// A number glued to a unit: `5 m`, `2.5 kg`.
    case quantity(Quantity, range: NSRange)
    /// A registered unit expression standing alone (the `day` in
    /// `3 hours / day` — the divisor is ONE day).
    case unit(UnitExpr, range: NSRange)
    /// `+ - * / ^ × ÷ of`
    case op(String, range: NSRange)
    /// `(` or `)`
    case paren(String, range: NSRange)
    /// A word run: a named value (`distance`), a grammar keyword
    /// (`to`, `in`, `as`) or an unknown word.
    case word(String, range: NSRange)
    /// A percent sign.
    case percent(range: NSRange)
}

// MARK: - Scanner

/// The bounded tokenizer of the mixed-unit language. Returns nil when
/// the line contains a character the language cannot express (the
/// line then falls to the legacy lanes: money markers, dates, prose).
enum MixedUnitScanner {
    static let opChars: Set<Character> = ["+", "-", "*", "/", "^", "×", "÷"]
    /// The compact-notation prefixes: `k K M G T P`.
    static let compactPrefixes: Set<Character> = ["k", "K", "M", "G", "T", "P"]

    /// The UTF-16 NSRange of a character-index slice of `line`
    /// (manual UTF-16 counting: stable for every source character).
    private static func range(of line: String, _ a: String.Index,
                              _ b: String.Index) -> NSRange {
        var loc = 0
        var i = line.startIndex
        while i < a {
            loc += line[i].utf16.count
            i = line.index(after: i)
        }
        var len = 0
        i = a
        while i < b {
            len += line[i].utf16.count
            i = line.index(after: i)
        }
        return NSRange(location: loc, length: len)
    }

    static func tokenize(_ line: String,
                         context: NumberFormatContext,
                         unitContext: UnitContext,
                         env: TypedEnv) -> [MToken]? {
        var out: [MToken] = []
        var i = line.startIndex
        while i < line.endIndex {
            let c = line[i]
            if c == " " || c == "\t" {
                i = line.index(after: i)
                continue
            }
            // --- number (optionally followed by a spaced unit) ---
            if c.isNumber || c == "." || c == "," {
                guard let (value, afterNum) =
                        Self.scanNumber(line, from: i, context: context)
                else { return nil }
                // A whitespace-separated unit word attaches the
                // quantity (`5 m`); a GLUED letter is compact notation
                // (already folded into `value` by the scanner), never
                // a unit.
                var j = afterNum
                if j < line.endIndex, line[j] == " " {
                    let w = line.index(after: j)  // space < endIndex, so w is safe

                    if w < line.endIndex,
                       Self.isUnitWordStart(line[w], context: context) {
                        let (word, wordEnd) = Self.scanWord(line, from: w)
                        // A LONE single-letter compact prefix with a
                        // space is compact notation, never a unit:
                        // `2 M` = two million. A LONGER word starting
                        // with a compact letter is a unit run: `20 km`
                        // is kilometres, `20 kg` kilograms.
                        if word.count == 1,
                           let first = word.first,
                           Self.compactPrefixes.contains(first) {
                            let after = wordEnd < line.endIndex
                                ? line.index(after: wordEnd) : wordEnd
                            let v = value * Self.compactFactor(first)
                            guard v.isFinite else { return nil }
                            out.append(.number(value: v,
                                               range: Self.range(of: line, i, after)))
                            i = after
                            continue
                        }
                        if let (u, afterUnit) = Self.scanUnitRun(line, from: w,
                                                                 context: context,
                                                                 unitContext: unitContext) {
                            out.append(.quantity(Quantity(value: value, display: u),
                                                 range: Self.range(of: line, i, afterUnit)))
                            i = afterUnit
                            continue
                        }
                    }
                }
                out.append(.number(value: value, range: Self.range(of: line, i, afterNum)))
                i = afterNum
                continue
            }
            // --- operators ---
            if Self.opChars.contains(c) || c == "×" || c == "÷" {
                let n = line.index(after: i)
                out.append(.op(String(c), range: Self.range(of: line, i, n)))
                i = n
                continue
            }
            if c == "(" || c == ")" {
                let n = line.index(after: i)
                out.append(.paren(String(c), range: Self.range(of: line, i, n)))
                i = n
                continue
            }
            if c == "%" {
                let n = line.index(after: i)
                out.append(.percent(range: Self.range(of: line, i, n)))
                i = n
                continue
            }
            // --- word run (letter-led) ---
            if c.isLetter || c == "µ" || c == "Ω" || c == "°" {
                let (word, afterWord) = Self.scanWord(line, from: i)
                let r = Self.range(of: line, i, afterWord)
                switch word {
                case "to", "in", "as":
                    out.append(.word(word, range: r))
                case "of":
                    out.append(.op("of", range: r))
                case "per", "for", "at", "ppi":
                    // The rate/PPI grammar words (r84): they mark the
                    // line as rate-shaped; the stage owners decide.
                    out.append(.word(word, range: r))
                default:
                    // A registered unit word (a bare unit operand) or
                    // a named value — the parser distinguishes.
                    if let u = unitContext.resolveToken(word),
                       unitContext.expr(of: u).isSpecial == false {
                        out.append(.unit(unitContext.expr(of: u), range: r))
                    } else {
                        out.append(.word(word, range: r))
                    }
                }
                i = afterWord
                continue
            }
            return nil // an unsupported character: strict
        }
        return out
    }

    /// A number with compact suffixes and a glued (compact) percent:
    /// `5m`, `2,5`, `1.2e3`, `20%`. The GLUED `k/M/G/T/P` is ALWAYS
    /// compact (quantity attachment requires whitespace, so `5m` can
    /// never be metres).
    private static func scanNumber(_ line: String, from start: String.Index,
                                   context: NumberFormatContext)
        -> (Double, String.Index)? {
        var i = start
        // The context decides which character is the DECIMAL separator
        // and which are GROUPING: legacy/NA groups with `,` (`1,000`),
        // decimal-comma locales group with `.` (`1.000,5`).
        let decimalChar: Character = context.decimalSeparator == "," ? "," : "."
        var grouping: Set<Character> = []
        for sep in context.inputGroupingSeparators {
            if let c = sep.first { grouping.insert(c) }
        }
        if let c = context.groupingSeparator.first { grouping.insert(c) }
        grouping.remove(decimalChar)
        var sawDecimal = false
        while i < line.endIndex {
            let c = line[i]
            if c.isNumber {
                i = line.index(after: i)
            } else if c == decimalChar {
                guard !sawDecimal else { break }  // two decimals: invalid
                sawDecimal = true
                i = line.index(after: i)
            } else if grouping.contains(c) {
                i = line.index(after: i)
            } else if c == "e" || c == "E" {
                i = line.index(after: i)
                if i < line.endIndex, line[i] == "+" || line[i] == "-" {
                    i = line.index(after: i)
                }
                while i < line.endIndex, line[i].isNumber {
                    i = line.index(after: i)
                }
                break
            } else if Self.compactPrefixes.contains(c) {
                // A glued compact prefix: `5m` = 5e6.
                i = line.index(after: i)
                break
            } else {
                break
            }
        }
        // A glued compact letter (consumed above) applies its factor.
        var value: Double
        var end = i
        let text = Self.numberText(line, start: start, end: i,
                                   decimalChar: decimalChar, grouping: grouping)
        guard let raw = Self.parseDouble(text) else { return nil }
        if i < line.endIndex,
           Self.compactPrefixes.contains(line[i]) {
            let f = Self.compactFactor(line[i])
            i = line.index(after: i)
            end = i
            value = raw * f
        } else {
            end = i
            value = raw
        }
        guard value.isFinite else { return nil }
        // A glued `%` folds into the number: `20%` = 0.2.
        if end < line.endIndex, line[end] == "%" {
            value /= 100
            guard value.isFinite else { return nil }
            end = line.index(after: end)
        }
        return (value, end)
    }

    /// Reconstruct the parseable text: strip grouping separators and
    /// map the decimal separator to a point.
    private static func numberText(_ line: String, start: String.Index,
                                   end: String.Index,
                                   decimalChar: Character,
                                   grouping: Set<Character>) -> String {
        var out = ""
        var i = start
        while i < end {
            let c = line[i]
            if grouping.contains(c) {
                // skip grouping separators
            } else if c == decimalChar {
                out += "."
            } else {
                out.append(c)
            }
            i = line.index(after: i)
        }
        return out
    }

    /// `Double(text)` with the regional fallbacks (a lone `.` is an
    /// invalid number, not zero).
    private static func parseDouble(_ text: String) -> Double? {
        guard !text.isEmpty else { return nil }
        if text == "." { return nil }
        guard let v = Double(text) else { return nil }
        return v
    }

    static func compactFactor(_ c: Character) -> Double {
        switch c {
        case "k", "K": return 1e3
        case "M": return 1e6
        case "G": return 1e9
        case "T": return 1e12
        case "P": return 1e15
        default: return 1
        }
    }

    /// A word start that can begin a UNIT word (letters, µ, Ω, °).
    private static func isUnitWordStart(_ c: Character,
                                        context: NumberFormatContext) -> Bool {
        c.isLetter || c == "µ" || c == "Ω" || c == "°"
    }

    /// A word: letters (plus µ Ω ° ² ³), with internal hyphens and
    /// periods, and a TRAILING digit run (`cm2` = cm², `100km`-style
    /// atoms inside expressions). A word is letter-led — a digit
    /// starts a number, never a word.
    private static func scanWord(_ line: String, from start: String.Index)
        -> (String, String.Index) {
        var i = start
        while i < line.endIndex {
            let c = line[i]
            if c.isLetter || c == "µ" || c == "Ω" || c == "°" ||
               c == "²" || c == "³" || c == "-" || c == "." {
                i = line.index(after: i)
            } else if c.isNumber, i > start {
                // Trailing digits only: `cm2`, `L100km` atoms.
                i = line.index(after: i)
            } else {
                break
            }
        }
        return (String(line[start..<i]), i)
    }

    /// A unit word run: the LONGEST registered unit expression that
    /// starts at `start` (multi-word units like `nautical miles`),
    /// including the trailing whitespace the run consumed.
    /// A unit RUN: space-separated words (up to three: `us ton-force`,
    /// `nautical miles`) plus GLUED expression continuations (`km/h`,
    /// `bbl/d`, `kgf/cm2` — a `/` or `*` with no surrounding space
    /// continues the unit expression). The LONGEST text that resolves
    /// to a non-special unit wins.
    static func scanUnitRun(_ line: String, from start: String.Index,
                            context: NumberFormatContext,
                            unitContext: UnitContext)
        -> (UnitExpr, String.Index)? {
        var cursor = start
        var text = ""
        var end = start
        var checkpoints: [(String, String.Index)] = []
        // Word pieces (space separated).
        while true {
            guard cursor < line.endIndex,
                  Self.isUnitWordStart(line[cursor], context: context) else { break }
            let (w, next) = Self.scanWord(line, from: cursor)
            if text.isEmpty { text = w } else { text += " " + w }
            end = next
            checkpoints.append((text, end))
            cursor = next
            // A glued expression operator continues the unit: `km/h/s`.
            if cursor < line.endIndex, line[cursor] == "/" || line[cursor] == "*" {
                let opChar = line[cursor]
                let afterOp = line.index(after: cursor)
                // The next atom: optional digit run + a letter word
                // (`L/100km`) or a bare digit-exponent unit (`km/2` is
                // NOT a unit — the atom must be letter-led).
                var atomStart = afterOp
                while atomStart < line.endIndex, line[atomStart].isNumber {
                    atomStart = line.index(after: atomStart)
                }
                guard atomStart < line.endIndex,
                      Self.isUnitWordStart(line[atomStart], context: context) else {
                    break
                }
                let (atom, atomEnd) = Self.scanWord(line, from: atomStart)
                text += String(opChar) + atom
                end = atomEnd
                checkpoints.append((text, end))
                cursor = atomEnd
                if text.count > 24 { break }
                continue
            }
            // A SPACE continues the word sequence (`us ton-force`).
            if cursor < line.endIndex, line[cursor] == " " {
                let afterSpace = line.index(after: cursor)
                guard afterSpace < line.endIndex,
                      Self.isUnitWordStart(line[afterSpace], context: context)
                else { break }
                cursor = afterSpace
                if text.count > 24 { break }
                continue
            }
            break
        }
        guard !text.isEmpty else { return nil }
        // Longest first: the longest prefix of the run that resolves
        // to a non-special unit wins; the span ends at that prefix's
        // last character so any rejected tail re-tokenizes normally.
        for (c, e) in checkpoints.reversed() {
            if let pe = unitContext.resolveExpression(c),
               pe.unit.isSpecial == false {
                var ee = e
                while ee < line.endIndex, line[ee] == " " { ee = line.index(after: ee) }
                return (pe.unit, ee)
            }
        }
        return nil
    }
}

// MARK: - Parser / evaluator

/// The recursive-descent parser over `MToken` streams. It evaluates
/// directly into `Quantity` values (no intermediate AST): precedence
/// mirrors the scalar engine — additive < multiplicative < power,
/// left-associative, with a right-associative `^` and unary minus.
enum MixedUnitParser {
    /// The evaluation environment for word operands: quantities and
    /// scalars from `env`; a currency/boolean/unknown name is a strict
    /// failure (never coerced, never stripped).
    static func quantity(for name: String, env: TypedEnv) -> Quantity? {
        guard let e = env.entry(display: name) else { return nil }
        switch e.qty {
        case .quantity(let q):
            return q
        case .scalar(let v, _, _) where v.isFinite:
            return .plain(v)
        default:
            return nil
        }
    }

    /// Evaluate a full mixed-unit line. `target` is the optional
    /// `to|in|as <unit>` suffix unit. Returns the result quantity, or
    /// nil when the line is malformed (the caller raises the generic
    /// hidden error — mixed-unit lines never fall through).
    static func evaluate(tokens: [MToken], env: TypedEnv,
                         context: NumberFormatContext,
                         rates: Rates,
                         unitContext: UnitContext,
                         target: UnitExpr?) -> Quantity? {
        var p = State(tokens: tokens, env: env, context: context,
                      rates: rates, unitContext: unitContext)
        guard let q = p.parseExpression() else { return nil }
        guard p.atEnd else { return nil }
        guard let target = target else { return q }
        return try? q.converted(to: target, rates: rates).get()
    }

    /// The parse state.
    final class State {
        let tokens: [MToken]
        let env: TypedEnv
        let context: NumberFormatContext
        let rates: Rates
        let unitContext: UnitContext
        var pos = 0
        init(tokens: [MToken], env: TypedEnv, context: NumberFormatContext,
             rates: Rates, unitContext: UnitContext) {
            self.tokens = tokens
            self.env = env
            self.context = context
            self.rates = rates
            self.unitContext = unitContext
        }
        var atEnd: Bool { pos >= tokens.count }
        func peek() -> MToken? { atEnd ? nil : tokens[pos] }
        func skip() { if !atEnd { pos += 1 } }
        func expectOp(_ ops: Set<String>) -> Bool {
            guard let tok = peek(), case .op(let o, range: _) = tok, ops.contains(o)
            else { return false }
            self.skip()
            return true
        }

        // MARK: levels

        /// expression := additive
        func parseExpression() -> Quantity? { parseAdditive() }

        /// additive := multiplicative { (+|-) multiplicative }
        func parseAdditive() -> Quantity? {
            guard var left = parseMultiplicative() else { return nil }
            while true {
                if expectOp(["+"]) {
                    guard let r = parseMultiplicative(),
                          let s = tryAdd(left, r, negative: false) else { return nil }
                    left = s
                } else if expectOp(["-"]) {
                    guard let r = parseMultiplicative(),
                          let s = tryAdd(left, r, negative: true) else { return nil }
                    left = s
                } else {
                    break
                }
            }
            return left
        }

        /// multiplicative := power { (*|/|×|÷|of) power }
        /// `of` multiplies (the percent-scaling reading: `50% of 200
        /// km` = 100 km; a unitless `50% of 200` stays in the
        /// percentage grammar and never reaches this parser).
        func parseMultiplicative() -> Quantity? {
            guard var left = parsePower() else { return nil }
            while true {
                if expectOp(["*", "×", "of"]) {
                    guard let r = parsePower(),
                          let s = tryMul(left, r, divide: false) else { return nil }
                    left = s
                } else if expectOp(["/", "÷"]) {
                    guard let r = parsePower(),
                          let s = tryMul(left, r, divide: true) else { return nil }
                    left = s
                } else if expectPer() {
                    // `per` is the spelled division: `90 km per 3 day`.
                    guard let r = parsePower(),
                          let s = tryMul(left, r, divide: true) else { return nil }
                    left = s
                } else {
                    break
                }
            }
            return left
        }

        /// The spelled division word (`per`): an operator where an
        /// operator is expected, never a unit or a named value.
        func expectPer() -> Bool {
            guard let tok = peek(), case .word(let w, range: _) = tok, w == "per"
            else { return false }
            self.skip()
            return true
        }

        /// power := unary [ ^ (2|3) ]  (right-associative, bounded)
        func parsePower() -> Quantity? {
            guard let base = parseUnary() else { return nil }
            if expectOp(["^"]) {
                guard let tok = peek(), case .number(let e, range: _) = tok else { return nil }
                guard e == 2 || e == 3 else { return nil }
                self.skip()
                return tryPower(base, Int(e))
            }
            return base
        }

        /// unary := -unary | primary
        func parseUnary() -> Quantity? {
            if expectOp(["-"]) {
                guard let q = parseUnary(),
                      let s = tryMul(Quantity.plain(-1), q, divide: false) else { return nil }
                return s
            }
            return parsePrimary()
        }

        /// primary := number | quantity | unit | ( expression ) | word
        func parsePrimary() -> Quantity? {
            guard let t = peek() else { return nil }
            self.skip()
            var q: Quantity?
            switch t {
            case .number(let v, range: _):
                q = .plain(v)
            case .quantity(let x, range: _):
                q = x
            case .unit(let u, range: _):
                // A bare unit is the multiplicative identity in that
                // unit: `3 hours / day` divides by ONE day.
                q = Quantity(value: 1, display: u)
            case .paren("(", range: _):
                guard let inner = parseExpression(),
                      expectOp([")"]) else { return nil }
                q = inner
            case .paren:
                return nil
            case .word(let w, range: _):
                if w == "to" || w == "in" || w == "as" { return nil }
                if w == "per" || w == "for" || w == "at" || w == "ppi" {
                    // Rate/PPI grammar words are owned by their own
                    // stages; a mixed expression never parses them.
                    return nil
                }
                q = MixedUnitParser.quantity(for: w, env: env)
            case .op, .percent:
                return nil
            }
            return q
        }

        // MARK: algebra wrappers

        func tryAdd(_ a: Quantity, _ b: Quantity, negative: Bool) -> Quantity? {
            let r = negative ? a.subtracted(b) : a.added(b)
            guard case .success(let q) = r else { return nil }
            return q
        }
        func tryMul(_ a: Quantity, _ b: Quantity, divide: Bool) -> Quantity? {
            let r = divide ? a.divided(b) : a.multiplied(b)
            guard case .success(let q) = r else { return nil }
            return q
        }
        func tryPower(_ a: Quantity, _ n: Int) -> Quantity? {
            let r = a.powered(n)
            guard case .success(let q) = r else { return nil }
            return q
        }
    }
}

// MARK: - Shape detection + line entry point

enum MixedUnitLine {
    /// Whether `line` is OWNED by the mixed-unit stage: it tokenizes
    /// cleanly, contains at least one `<number>␣<unit>` quantity
    /// literal, and is expression-shaped (an operator, a target
    /// conversion, or a bare quantity line). Lines without a quantity
    /// literal (plain math, percentages, prose) are untouched, and a
    /// single unsupported character (a currency marker, an emoji)
    /// keeps the line in the legacy lanes.
    static func shape(_ line: String,
                      context: NumberFormatContext,
                      unitContext: UnitContext,
                      env: TypedEnv,
                      now: Date = Date(),
                      calendar: Calendar = .current) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        // Valid date lines own their duration words (`May 5 + 43
        // days`): the quantity stage must never steal them. A
        // MALFORMED date shape is NOT owned — it still reaches the
        // date lane below (and errors exactly as before).
        if case .value = DateArithmetic.detect(line: line, now: now,
                                               calendar: calendar) {
            return false
        }
        let (body, target) = Self.splitTarget(line)
        guard let tokens = MixedUnitScanner.tokenize(body, context: context,
                                                     unitContext: unitContext,
                                                     env: env) else { return false }
        var hasQuantity = false
        var hasOperator = false
        let bodyNS = body as NSString
        for (idx, t) in tokens.enumerated() {
            if case .quantity = t { hasQuantity = true }
            if case .word(let w, range: _) = t, w == "per" {
                hasOperator = true
            }
            if case .op(let o, range: let r) = t {
                // A GLUED `/` (no surrounding whitespace) between two
                // unit-side tokens is part of a unit expression
                // (`10 km/L`, `1 km/h/s`), not arithmetic. A spaced
                // `/` is always arithmetic (`90 km / 3 day`).
                if o == "/" || o == "*" {
                    let prev = idx > 0 ? tokens[idx - 1] : nil
                    let next = idx + 1 < tokens.count ? tokens[idx + 1] : nil
                    let beforeGlued = r.location == 0 ||
                        bodyNS.character(at: r.location - 1) == 47 ||
                        bodyNS.character(at: r.location - 1) != 32
                    let afterEnd = r.location + r.length
                    let afterGlued = afterEnd >= bodyNS.length ||
                        bodyNS.character(at: afterEnd) != 32
                    if beforeGlued && afterGlued,
                       let a = prev, let b = next,
                       Self.isUnitSide(a), Self.isUnitSide(b) {
                        continue
                    }
                }
                hasOperator = true
            }
        }
        guard hasQuantity else { return false }
        // No top-level OPERATOR: a bare quantity (`10 km`) is ours; a
        // `<value unit> to|in|as <unit expression>` shape and a
        // parenthesized qualifier (`1 hp (electric)`) are owned by
        // the legacy conversion lane (it understands FULL unit
        // expressions: `1 km/h/s to m/s²`, `1 bbl/d to L/s`,
        // `10 km/L to US mpg`).
        if !hasOperator {
            if target != nil { return false }
            if tokens.count == 1 { return true }
            // `<quantity> ( word )` — the qualifier form.
            if tokens.count == 4,
               case .quantity = tokens[0],
               case .paren = tokens[1],
               case .word = tokens[2],
               case .paren = tokens[3] {
                return false
            }
            return false
        }
        // Operators present: parentheses make it an expression.
        return true
    }

    /// Evaluates a mixed-unit line end to end. Returns the result
    /// quantity, or nil (the caller raises the generic hidden error —
    /// a shape-owned line never falls through to word stripping).
    static func evaluate(_ line: String, env: TypedEnv,
                         context: NumberFormatContext, rates: Rates,
                         unitContext: UnitContext,
                         now: Date = Date(),
                         calendar: Calendar = .current) -> Quantity? {
        if case .value = DateArithmetic.detect(line: line, now: now,
                                               calendar: calendar) {
            return nil
        }
        // Peel an optional trailing ` to|in|as <unit expression>`
        // target: the target is the TEXT after the LAST space-delimited
        // keyword (compound targets like `km/h`, `m / s`, `pt (type)`
        // stay one resolved expression).
        let (body, targetText) = Self.splitTarget(line)
        var target: UnitExpr?
        if let t = targetText {
            target = Self.resolveTarget(t, unitContext: unitContext)
            // A shape-owned line with a target that does not resolve
            // is a strict error (never a silent target drop).
            if target == nil { return nil }
        }
        guard let tokens = MixedUnitScanner.tokenize(body, context: context,
                                                     unitContext: unitContext,
                                                     env: env) else { return nil }
        return MixedUnitParser.evaluate(tokens: tokens, env: env, context: context,
                                        rates: rates, unitContext: unitContext,
                                        target: target)
    }

    /// Splits the line at its LAST space-delimited `to`/`in`/`as`
    /// keyword. Returns the body prefix and the target unit TEXT (nil
    /// when no keyword is present). The keyword must be a whole word
    /// surrounded by whitespace (or line start/end).
    static func splitTarget(_ line: String) -> (body: String, target: String?) {
        let lower = line.lowercased()
        var best = -1
        for kw in [" to ", " in ", " as "] {
            var from = lower.startIndex
            while let r = lower.range(of: kw, range: from..<lower.endIndex) {
                best = max(best, line.distance(from: line.startIndex, to: r.lowerBound))
                from = r.upperBound
            }
        }
        guard best >= 0 else { return (line, nil) }
        let kwStart = line.index(line.startIndex, offsetBy: best)
        let body = String(line[line.startIndex..<kwStart])
        let target = String(line[line.index(kwStart, offsetBy: 4)...])
            .trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return (line, nil) }
        return (body, target)
    }

    /// Resolves the target TEXT (the text after the last `to|in|as`)
    /// to a unit expression: expression grammar first (`km/h`,
    /// `m / s`, `pt (type)`), display label second.
    static func isUnitToken(_ t: MToken) -> Bool {
        if case .unit = t { return true }
        return false
    }

    /// A token that can sit on the unit side of a unit-expression
    /// slash: a bare unit or a quantity literal (`10 km/L` — the `km`
    /// lives inside the quantity token).
    static func isUnitSide(_ t: MToken) -> Bool {
        switch t {
        case .unit, .quantity: return true
        default: return false
        }
    }

    /// Resolves the target TEXT (the text after the last `to|in|as`)
    /// to a unit expression: expression grammar first (`km/h`,
    /// `m / s`, `pt (type)`), display label second. Special targets
    /// (currency, temperature, fuel economy) are allowed: the shared
    /// `convertValue` engine decides the crossing.
    static func resolveTarget(_ text: String,
                              unitContext: UnitContext) -> UnitExpr? {
        if let pe = unitContext.resolveExpression(text) {
            return pe.unit
        }
        if let e = unitContext.resolveLabel(text) {
            return e
        }
        return nil
    }
}
