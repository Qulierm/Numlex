//  PercentageGrammar.swift
//  Numlex
//
//  Copyright © 2025 Andrei. MIT license.
//
//  r83: the ONE strict percentage-phrase grammar.
//
//  The engine already understands percent LITERALS (`10% = 0.1`, `200 *
//  10% = 20`, the contextual `100 + 10% = 110`) — those stay in the
//  expression parser with their values preserved and their NEW semantic
//  kind (percent-kind results display as `30%`, not `0.3`).
//
//  This grammar adds the WORD forms, each strict and keyword-aware
//  (an active variable named like a keyword — `of = 5` — kills the
//  forms that use it):
//
//      15% of 490          73.5     (percent-ish × value; money value
//                                     of the right operand)
//      15% on 200          230      (value × (1 + percent))
//      30% off 200         140      (value × (1 − percent))
//      100 is 50% of what  200      (reverse base: value ÷ ratio)
//      100 is 20% off what 125      (value ÷ (1 − ratio))
//      100 is 25% on what  80       (value ÷ (1 + ratio))
//      50 is what % of 200 25%      (value ÷ value, as a percent)
//      140 is what % off 200 30%
//      230 is what % on 200 15%
//      100 as a % of 800    12.5%   (value ÷ value, as a percent)
//      100 to 130 is what % 30%     ((new − old) ÷ old, as a percent)
//      100 to 130 as %      30%
//      1.5x of 20           30      (multiplier literals and the
//      1.5x on 20           50      `x` suffix; on/off use it as a
//      1.5x off 20          10      change magnitude, so a 100% change
//                                     doubles/halves)
//      20/200 %             10%     (the TERMINAL spaced % converts the
//      2/3 %                66.7%   whole preceding division to a
//                                     percent; `20/200%` keeps the legacy
//                                     postfix reading, still 10)
//      50% as fraction      1/2     (reduced rational)
//      2/10 as fraction     1/5
//      0.25 as %            25%
//      20 as x of 5         4x      (plain ratio, as a multiplier)
//      10 to 15 as x        1.5x
//      20% is 500, what is 750   17.5%  (ratio: B × L ÷ A)
//      if 500 is 20%, what is 750   30%    (A × C ÷ B, plain)
//
//  Operand values are evaluated by the ONE strict engine (named values
//  resolved with placeholders, money markers and money names through
//  the money core, residual identifiers fail). A percent-kind,
//  multiplier-kind, fraction-kind, or simple-division operand qualifies
//  as a "percent-ish" magnitude; a plain number does not. Money
//  operands participate when a form's constraints allow (the value side
//  of `of`/reverse-base, the base of `on`/`off`); a form that DIVIDES
//  money (`50 is what % of 200` with mixed currencies) errors instead
//  of mixing units. Nothing here coerces a boolean or a currency.

import Foundation

public enum PercentageGrammar {

    // MARK: - outcomes

    public enum Outcome: Equatable {
        /// No phrase form matched (structural OR gate failure) — the
        /// caller falls through to the other routes, exactly as today.
        case notPercent
        /// A matched form, evaluated.
        case value(LineResult)
        /// A matched form that FAILED (malformed operand, mixed
        /// currencies, zero base, non-finite) — surfaced, never
        /// degraded to another route.
        case error(String)
    }

    // MARK: - keyword handling

    /// Every keyword word of the phrase grammar. A form is live only
    /// when NONE of its keywords is shadowed by an active variable or
    /// constant (an `of = 5` assignment kills every `of` form for the
    /// rest of the sheet, like the r82 boolean keywords).
    static let allKeywords: Set<String> = [
        "of", "on", "off", "is", "what", "as", "a", "to",
        "percent", "percentage", "fraction",
        "multiple", "multiplier", "x", "if",
    ]

    static func keywordLive(_ word: String, env: TypedEnv) -> Bool {
        !env.shadowsKeyword(word)
    }

    // MARK: - pieces

    /// A slice of a phrase line: an ASCII word, or the non-word text
    /// (an operand span: numbers, operators, currency markers, the `%`
    /// symbol) that sits between words.
    struct Piece {
        enum Kind { case word(String); case span }
        let kind: Kind
        /// The exact slice of the line (spans keep inner spaces; the
        /// evaluator trims and strips surrounding commas).
        let text: String

        var isWord: Bool { if case .word = kind { return true }; return false }
        func word() -> String? { if case .word(let w) = kind { return w }; return nil }
    }

    /// Split a line into pieces. A piece is either an ASCII word (a
    /// LETTER-led run of letters/digits — variable names, keywords,
    /// the `r83tok` token placeholders) or an operand span: the
    /// non-word text between words (numbers, digits-led runs, the `%`
    /// symbol, operators, currency markers). Pure-space runs vanish:
    /// words/operands are separated by whitespace no slot needs.
    /// Returns nil when the line has no structure at all.
    static func pieces(of line: String) -> [Piece]? {
        var out: [Piece] = []
        var i = line.startIndex
        let isWordStart: (Character) -> Bool = { c in
            c.isASCII && c.isLetter
        }
        let isWordCont: (Character) -> Bool = { c in
            c.isASCII && (c.isLetter || c.isNumber)
        }
        while i < line.endIndex {
            if isWordStart(line[i]) {
                let start = i
                i = line.index(after: i)
                while i < line.endIndex, isWordCont(line[i]) { i = line.index(after: i) }
                let w = String(line[start..<i]).lowercased()
                out.append(Piece(kind: .word(w), text: String(line[start..<i])))
            } else if line[i] == " " {
                // Whitespace separates pieces: skip it.
                i = line.index(after: i)
            } else {
                let start = i
                // A SPAN: a run of non-word, non-space characters.
                // WHITESPACE breaks the run (it separates pieces —
                // `20% , what` is three pieces, not one), so a span
                // never absorbs the comma of a ratio form or the
                // space of a terminal spaced-% conversion.
                while i < line.endIndex, !isWordStart(line[i]), line[i] != " " {
                    i = line.index(after: i)
                }
                let span = line[start..<i]
                let trimmed = String(span).trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    var text = String(span)
                    // A glued multiplier suffix: the span run stopped
                    // on the letter `x` immediately after a digit-led
                    // span — fold it back in so `1.5x` is ONE operand
                    // piece (a SPACED `1.5 x` still reads as the
                    // variable x).
                    if i < line.endIndex, line[i] == "x", let first = text.first,
                       first.isNumber {
                        i = line.index(after: i)
                        text += "x"
                    }
                    // A trailing comma is the ratio punctuation, not
                    // part of the operand (`20% , what`): split it
                    // into its own piece. A thousands comma inside a
                    // number never ends the span, so this only ever
                    // fires on the standalone ratio comma.
                    if text.hasSuffix(","), text.count > 1,
                       !text.dropLast().contains(",") {
                        text.removeLast()
                        out.append(Piece(kind: .span, text: text))
                        out.append(Piece(kind: .span, text: ","))
                    } else {
                        out.append(Piece(kind: .span, text: text))
                    }
                }
            }
        }
        return out
    }

    /// Whether a SPAN piece can continue an operand expression: a
    /// leading digit, an operator glyph, a bracket, `%`, or a
    /// currency marker. A lone punctuation piece (the ratio comma)
    /// never extends — it ends the run and is matched by its own
    /// `.punct` slot.
    static func extendsOperand(_ p: Piece) -> Bool {
        guard !p.isWord else { return false }
        let t = p.text.trimmingCharacters(in: .whitespaces)
        guard let f = t.first else { return false }
        if f.isNumber { return true }
        if "+-/*÷×%^()[]{}".contains(f) { return true }
        if f == "$" || f == "€" || f == "£" { return true }
        return false
    }

    // MARK: - template slots

    enum Slot {
        case word(String)   // an exact (lowercased) keyword
        case operand        // a non-empty span, or a single word piece (a named value)
        case pct            // the `%` symbol span, or the words percent/percentage
        case multKw         // x | multiple | multiplier (all must be live)
        case punct(String)  // an exact symbol span (the ratio comma)
    }

    struct OperandValue {
        var value: Double
        var kind: NumericKind
        var shape: OperandShape
        var currency: String?
        var fraction: Rational?

        /// A percent-ish magnitude: a percent literal, a multiplier
        /// literal, a fraction-kind value, or a simple division — the
        /// kinds the `of`/`on`/`off` left operand accepts.
        var isPercentish: Bool {
            switch shape {
            case .percent, .multiplier, .fraction:
                return true
            case .plain:
                return false
            }
        }
    }

    /// A matched form: the template, its keyword set, and the
    /// evaluator over the operand values.
    struct Form {
        let slots: [Slot]
        let keywords: Set<String>
        let eval: ([OperandValue]) -> LineResult?

        func live(env: TypedEnv) -> Bool {
            keywords.allSatisfy { keywordLive($0, env: env) }
        }
    }

    // MARK: - operand evaluation

    /// Evaluate an operand span (or a named word) through the ONE
    /// strict engine. Money markers and money names resolve through
    /// the money core; everything else through the typed expression
    /// engine (which carries percent/multiplier kinds). A residual
    /// identifier (an unknown name, a broken token) fails — the
    /// operand is malformed, and so is the phrase.
    /// `table` overrides the environment projection (the token route
    /// passes its placeholder table).
    static func operandValue(_ text: String, named: String?,
                             env: TypedEnv,
                             context: NumberFormatContext,
                             table: [String: TypedScalar]? = nil) -> OperandValue? {
        let envCopy = env
        let baseTable = table ?? typedTable(env)
        var src = text
        if let named = named {
            // A single-word operand is a NAMED VALUE: substitute it
            // with its real (kinded) quantity; otherwise it enters as
            // an identifier and the residual guard decides (unknown
            // names fail, active names resolve).
            if env.entry(display: named) != nil || baseTable[named] != nil {
                src = src.replacingOccurrences(of: named, with: "\u{1}")
            }
        }
        // Money first (markers and money names), then the strict typed
        // engine. A malformed money operand fails the whole phrase.
        let money = NaturalCalculation.moneyOutcome(src, env: envCopy, context: context)
        switch money {
        case .money(let v, let code):
            return OperandValue(value: v, kind: .plain, shape: .plain, currency: code, fraction: nil)
        case .malformed:
            return nil
        case .none:
            break
        }
        guard let (value, kind, shape) = try? evaluateOperand(src, variables: baseTable, context: context) else { return nil }
        guard value.isFinite else { return nil }
        var o = OperandValue(value: value, kind: kind, shape: shape, currency: nil, fraction: nil)
        if shape == .fraction {
            o.fraction = Rational.fromDouble(value)
        }
        return o
    }

    // MARK: - the forms

    /// Build every phrase form whose keywords are live in `env`.
    static func forms(env: TypedEnv) -> [Form] {
        var out: [Form] = []

        // 15% of 490 → 73.5 (left percent-ish; right may be money —
        // the result takes the right currency)
        out.append(Form(slots: [.operand, .word("of"), .operand], keywords: ["of"]) { ops in
            guard ops.count == 2, ops[0].isPercentish else { return nil }
            let r = ops[1]
            let v = ops[0].value * r.value
            guard v.isFinite else { return nil }
            return r.currency.map { .money(value: v, code: $0) }
                ?? .number(value: v, unit: nil)
        })

        // 15% on 200 → 230 (1.5x on 20 → 50: a multiplier is a
        // change magnitude, so 100% doubles)
        out.append(Form(slots: [.operand, .word("on"), .operand], keywords: ["on"]) { ops in
            guard ops.count == 2, ops[0].isPercentish else { return nil }
            let a = ops[0].value
            let b = ops[1].value
            let v = b * (1 + a)
            guard v.isFinite else { return nil }
            return ops[1].currency.map { .money(value: v, code: $0) }
                ?? .number(value: v, unit: nil)
        })

        // 30% off 200 → 140
        out.append(Form(slots: [.operand, .word("off"), .operand], keywords: ["off"]) { ops in
            guard ops.count == 2, ops[0].isPercentish else { return nil }
            let a = ops[0].value
            let b = ops[1].value
            let v = b * (1 - a)
            guard v.isFinite else { return nil }
            return ops[1].currency.map { .money(value: v, code: $0) }
                ?? .number(value: v, unit: nil)
        })

        // 100 is 50% of what → 200 (reverse base)
        out.append(Form(slots: [.operand, .word("is"), .operand, .word("of"), .word("what")],
                        keywords: ["is", "of", "what"]) { ops in
            guard ops.count == 2, ops[1].isPercentish else { return nil }
            let l = ops[0].value
            let m = ops[1].value
            guard m != 0, (l / m).isFinite else { return nil }
            return ops[0].currency.map { .money(value: l / m, code: $0) }
                ?? .number(value: l / m, unit: nil)
        })

        // 100 is 20% off what → 125
        out.append(Form(slots: [.operand, .word("is"), .operand, .word("off"), .word("what")],
                        keywords: ["is", "off", "what"]) { ops in
            guard ops.count == 2, ops[1].isPercentish else { return nil }
            let base = 1 - ops[1].value
            let l = ops[0].value
            guard base != 0, (l / base).isFinite else { return nil }
            return ops[0].currency.map { .money(value: l / base, code: $0) }
                ?? .number(value: l / base, unit: nil)
        })

        // 100 is 25% on what → 80
        out.append(Form(slots: [.operand, .word("is"), .operand, .word("on"), .word("what")],
                        keywords: ["is", "on", "what"]) { ops in
            guard ops.count == 2, ops[1].isPercentish else { return nil }
            let base = 1 + ops[1].value
            let l = ops[0].value
            guard base != 0, (l / base).isFinite else { return nil }
            return ops[0].currency.map { .money(value: l / base, code: $0) }
                ?? .number(value: l / base, unit: nil)
        })

        // 50 is what % of 200 → 25% (both sides must be currency-free
        // or the SAME currency — mixed currencies error)
        out.append(Form(slots: [.operand, .word("is"), .word("what"), .pct, .word("of"), .operand],
                        keywords: ["is", "what", "of"]) { ops in
            guard ops.count == 2 else { return nil }
            guard ops[0].currency == ops[1].currency else { return nil }
            let l = ops[0].value, r = ops[1].value
            guard r != 0, (l / r).isFinite else { return nil }
            return .percent(value: l / r)
        })

        // 140 is what % off 200 → 30%
        out.append(Form(slots: [.operand, .word("is"), .word("what"), .pct, .word("off"), .operand],
                        keywords: ["is", "what", "off"]) { ops in
            guard ops.count == 2 else { return nil }
            guard ops[0].currency == ops[1].currency else { return nil }
            let l = ops[0].value, r = ops[1].value
            guard r != 0, ((r - l) / r).isFinite else { return nil }
            return .percent(value: (r - l) / r)
        })

        // 230 is what % on 200 → 15%
        out.append(Form(slots: [.operand, .word("is"), .word("what"), .pct, .word("on"), .operand],
                        keywords: ["is", "what", "on"]) { ops in
            guard ops.count == 2 else { return nil }
            guard ops[0].currency == ops[1].currency else { return nil }
            let l = ops[0].value, r = ops[1].value
            guard r != 0, ((l - r) / r).isFinite else { return nil }
            return .percent(value: (l - r) / r)
        })

        // 100 as a % of 800 → 12.5% (the `a` article is optional)
        out.append(Form(slots: [.operand, .word("as"), .pct, .word("of"), .operand],
                        keywords: ["as", "of"]) { ops in
            guard ops.count == 2 else { return nil }
            guard ops[0].currency == ops[1].currency else { return nil }
            let l = ops[0].value, r = ops[1].value
            guard r != 0, (l / r).isFinite else { return nil }
            return .percent(value: l / r)
        })
        out.append(Form(slots: [.operand, .word("as"), .word("a"), .pct, .word("of"), .operand],
                        keywords: ["as", "a", "of"]) { ops in
            guard ops.count == 2 else { return nil }
            guard ops[0].currency == ops[1].currency else { return nil }
            let l = ops[0].value, r = ops[1].value
            guard r != 0, (l / r).isFinite else { return nil }
            return .percent(value: l / r)
        })

        // 100 to 130 is what % → 30% (change vs the first value)
        out.append(Form(slots: [.operand, .word("to"), .operand, .word("is"), .word("what"), .pct],
                        keywords: ["to", "is", "what"]) { ops in
            guard ops.count == 2 else { return nil }
            guard ops[0].currency == ops[1].currency else { return nil }
            let l = ops[0].value, r = ops[1].value
            guard l != 0, ((r - l) / l).isFinite else { return nil }
            return .percent(value: (r - l) / l)
        })

        // 100 to 130 as % → 30% (the `a` article is optional)
        out.append(Form(slots: [.operand, .word("to"), .operand, .word("as"), .pct],
                        keywords: ["to", "as"]) { ops in
            guard ops.count == 2 else { return nil }
            guard ops[0].currency == ops[1].currency else { return nil }
            let l = ops[0].value, r = ops[1].value
            guard l != 0, ((r - l) / l).isFinite else { return nil }
            return .percent(value: (r - l) / l)
        })
        out.append(Form(slots: [.operand, .word("to"), .operand, .word("as"), .word("a"), .pct],
                        keywords: ["to", "as", "a"]) { ops in
            guard ops.count == 2 else { return nil }
            guard ops[0].currency == ops[1].currency else { return nil }
            let l = ops[0].value, r = ops[1].value
            guard l != 0, ((r - l) / l).isFinite else { return nil }
            return .percent(value: (r - l) / l)
        })

        // 50% as fraction → 1/2; 2/10 as fraction → 1/5;
        // 0.25 (plain) as fraction → 1/4. Multiplier and currency
        // operands are rejected.
        out.append(Form(slots: [.operand, .word("as"), .word("fraction")],
                        keywords: ["as", "fraction"]) { ops in
            guard ops.count == 1, ops[0].currency == nil else { return nil }
            guard ops[0].shape != .multiplier else { return nil }
            guard let f = ops[0].fraction ?? Rational.fromDouble(ops[0].value) else { return nil }
            return .fraction(f)
        })
        out.append(Form(slots: [.operand, .word("as"), .word("a"), .word("fraction")],
                        keywords: ["as", "a", "fraction"]) { ops in
            guard ops.count == 1, ops[0].currency == nil else { return nil }
            guard ops[0].shape != .multiplier else { return nil }
            guard let f = ops[0].fraction ?? Rational.fromDouble(ops[0].value) else { return nil }
            return .fraction(f)
        })

        // 0.25 as % → 25% (a PLAIN or FRACTION number becomes a
        // percent; a percent, multiplier, or currency operand is
        // rejected)
        out.append(Form(slots: [.operand, .word("as"), .pct],
                        keywords: ["as"]) { ops in
            guard ops.count == 1, ops[0].currency == nil else { return nil }
            guard ops[0].shape == .plain || ops[0].shape == .fraction else { return nil }
            return .percent(value: ops[0].value)
        })
        out.append(Form(slots: [.operand, .word("as"), .word("a"), .pct],
                        keywords: ["as", "a"]) { ops in
            guard ops.count == 1, ops[0].currency == nil else { return nil }
            guard ops[0].shape == .plain || ops[0].shape == .fraction else { return nil }
            return .percent(value: ops[0].value)
        })

        // 20 as x of 5 → 4x (plain ratio as a multiplier; percent
        // and currency operands rejected, zero base fails)
        for kw in ["x", "multiple", "multiplier"] {
            out.append(Form(slots: [.operand, .word("as"), .multKw, .word("of"), .operand],
                            keywords: ["as", kw, "of"]) { ops in
                guard ops.count == 2 else { return nil }
                guard ops[0].currency == nil, ops[1].currency == nil else { return nil }
                guard ops[0].shape == .plain, ops[1].shape == .plain else { return nil }
                let l = ops[0].value, r = ops[1].value
                guard r != 0, (l / r).isFinite else { return nil }
                return .multiplier(value: l / r)
            })
        }

        // 10 to 15 as x → 1.5x
        for kw in ["x", "multiple", "multiplier"] {
            out.append(Form(slots: [.operand, .word("to"), .operand, .word("as"), .multKw],
                            keywords: ["to", "as", kw]) { ops in
                guard ops.count == 2 else { return nil }
                guard ops[0].currency == nil, ops[1].currency == nil else { return nil }
                guard ops[0].shape == .plain, ops[1].shape == .plain else { return nil }
                let l = ops[0].value, r = ops[1].value
                guard l != 0, (r / l).isFinite else { return nil }
                return .multiplier(value: r / l)
            })
        }

        // 20% is 500, what is 750 → 17.5% (ratio: B × L ÷ A, L a
        // percent-ish magnitude; A, B plain values, currency on A
        // allowed)
        out.append(Form(slots: [.operand, .word("is"), .operand, .punct(","),
                                .word("what"), .word("is"), .operand],
                        keywords: ["is", "what"]) { ops in
            guard ops.count == 3, ops[0].isPercentish else { return nil }
            guard ops[1].currency == ops[2].currency else { return nil }
            let a = ops[1].value, b = ops[2].value
            guard a != 0, (b * ops[0].value / a).isFinite else { return nil }
            return .percent(value: b * ops[0].value / a)
        })

        // if 500 is 20%, what is 750 → 30% (A × C ÷ B, B, C
        // percent-ish; the result keeps A's currency)
        out.append(Form(slots: [.word("if"), .operand, .word("is"), .operand,
                                .punct(","), .word("what"), .word("is"), .operand],
                        keywords: ["if", "is", "what"]) { ops in
            guard ops.count == 3 else { return nil }
            let a = ops[0], b = ops[1], c = ops[2]
            guard a.currency == nil, c.currency == nil,
                  b.shape == .percent, !a.value.isZero,
                  (c.value * b.value / a.value).isFinite else { return nil }
            // Proportional: `if A is B%, what is C` → C × B / A,
            // answering in percent (750 × 20% / 500 = 30%).
            return .number(value: c.value * b.value / a.value, unit: nil, kind: .percent, fraction: nil)
        })

        return out.filter { $0.live(env: env) }
    }

    // MARK: - matching

    /// The structural match of one form against the line's pieces.
    /// `dangling`: the pieces ran out mid-form after a valid prefix
    /// whose NEXT expected slot is an operand — a phrase missing its
    /// value operand (`50 is what % of`) is MALFORMED, not a legacy
    /// reading: it errors instead of degrading to word-stripping.
    enum MatchResult {
        case none
        case matched([Piece])
        case dangling
    }

    /// Try every live form against the line's pieces. A form matches
    /// when its slots consume ALL pieces in order: a word slot wants
    /// the exact word, an operand slot a non-empty span, a single
    /// word that is not a grammar keyword (a named value — multi-word
    /// declared names count as one operand when the consecutive words
    /// name one), a pct slot the `%` symbol span or the
    /// percent/percentage word, a mult slot one of its keywords.
    static func match(line: String, env: TypedEnv) -> (form: Form, operandPieces: [Piece])? {
        guard let pcs = pieces(of: line), !pcs.isEmpty else { return nil }
        return match(pcs: pcs, env: env)
    }

    static func match(pcs: [Piece], env: TypedEnv) -> (form: Form, operandPieces: [Piece])? {
        for form in forms(env: env) {
            if case .matched(let ops) = matchResult(form: form, pcs: pcs, env: env) {
                return (form, ops)
            }
        }
        return nil
    }

    /// The structural result of one form (see `MatchResult`). A
    /// multi-word declared name (a run of consecutive word pieces
    /// that names one active value, longest first) is consumed as a
    /// single named operand.
    static func matchResult(form: Form, pcs: [Piece], env: TypedEnv) -> MatchResult {
        var i = 0
        var ops: [Piece] = []
        for slot in form.slots {
            if i >= pcs.count {
                // Pieces exhausted mid-form: the consumed prefix was
                // valid (word slots matched exactly); dangling only
                // when the missing piece is a VALUE operand.
                if case .operand = slot { return .dangling }
                return .none
            }
            let p = pcs[i]
            switch slot {
            case .word(let w):
                guard case .word(let pw) = p.kind, pw == w else { return .none }
                i += 1
            case .operand:
                if p.isWord {
                    if case .word(let pw) = p.kind, PercentageGrammar.allKeywords.contains(pw) {
                        return .none
                    }
                    // A multi-word declared name: the longest run of
                    // consecutive word pieces starting here that names
                    // one active value (`monthly rent`).
                    var runEnd = i
                    var found: Piece? = nil
                    while runEnd + 1 < pcs.count, pcs[runEnd + 1].isWord,
                          !PercentageGrammar.allKeywords.contains(pcs[runEnd + 1].word() ?? "") {
                        runEnd += 1
                        let nameText = pcs[i...runEnd].map { $0.text }.joined(separator: " ")
                        if env.entry(display: nameText) != nil {
                            found = Piece(kind: .word(nameText.lowercased()), text: nameText)
                            break
                        }
                    }
                    if let found = found {
                        ops.append(found)
                        i = runEnd + 1
                    } else {
                        ops.append(p)
                        i += 1
                    }
                } else {
                    // A span operand: the maximal run of adjacent
                    // span pieces (operator glyphs, continued numbers)
                    // is ONE expression — `2 / 10` is a single
                    // operand even when the canonicalizer spaced the
                    // operator. A word (keyword or name) or a lone
                    // punctuation piece (the ratio comma) ends the run.
                    var text = p.text
                    var j = i
                    while j + 1 < pcs.count,
                          !pcs[j + 1].isWord,
                          PercentageGrammar.extendsOperand(pcs[j + 1]) {
                        j += 1
                        text += " " + pcs[j].text
                    }
                    ops.append(Piece(kind: .span, text: text))
                    i = j + 1
                }
            case .pct:
                if p.isWord {
                    if case .word(let pw) = p.kind {
                        guard pw == "percent" || pw == "percentage" else { return .none }
                    }
                } else {
                    let t = p.text.trimmingCharacters(in: .whitespaces)
                    guard t == "%" else { return .none }
                }
                i += 1
            case .multKw:
                guard case .word(let pw) = p.kind,
                      pw == "x" || pw == "multiple" || pw == "multiplier" else { return .none }
                i += 1
            case .punct(let s):
                guard !p.isWord, p.text.trimmingCharacters(in: .whitespaces) == s
                else { return .none }
                i += 1
            }
        }
        guard i == pcs.count else { return .none }
        return .matched(ops)
    }

    // MARK: - terminal spaced-% conversion

    /// The TERMINAL spaced `%` conversion: a line that ends with ` %`
    /// (whitespace before the symbol, at end of line) whose preceding
    /// expression is a division chain (`20/200 %`, `2/3 %`, `x/2 %`)
    /// converts that WHOLE expression to a percent. `20/200%` (no
    /// space) keeps the legacy postfix reading (percent binds to the
    /// last number, 20 ÷ 2 = 10), and `50 %` (a plain literal) stays
    /// the legacy `50%` → 0.5.
    static func spacedTerminalPercent(line: String, env: TypedEnv,
                                      context: NumberFormatContext,
                                      table: [String: TypedScalar]? = nil) -> Outcome? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix("%") else { return nil }
        // The trailing run of `%` glyphs (a legacy double-percent
        // never starts with a space, so it can never be a conversion).
        var cut = trimmed.endIndex
        while cut > trimmed.startIndex,
              trimmed[trimmed.index(before: cut)] == "%" {
            cut = trimmed.index(before: cut)
        }
        // `cut` now points at the first trailing `%`; the explicit
        // SPACE is what makes the conversion — the character right
        // before the `%` run must be one.
        guard cut > trimmed.startIndex,
              trimmed[trimmed.index(before: cut)] == " "
        else { return nil }
        let prefix = String(trimmed[..<trimmed.index(before: cut)]).trimmingCharacters(in: .whitespaces)
        // The prefix must be a pure numeric chain: a letter anywhere
        // (a word like `as` in `1/3 as %`) means this is not the
        // spaced conversion but a phrase the form table owns.
        guard !prefix.isEmpty,
              !prefix.contains(where: { $0.isLetter }),
              topLevelLastOperator(prefix) == "/" || topLevelLastOperator(prefix) == "÷"
        else { return nil }
        guard let op = operandValue(prefix, named: nil, env: env, context: context, table: table) else {
            return .error("Invalid expression")
        }
        return .value(.percent(value: op.value))
    }

    /// The last top-level (paren-depth 0) arithmetic operator in the
    /// text, if any.
    static func topLevelLastOperator(_ text: String) -> Character? {
        var depth = 0
        var last: Character? = nil
        for c in text where c != " " {
            switch c {
            case "(", "[", "{": depth += 1
            case ")", "]", "}": depth -= 1
            case "+", "-", "*", "/", "×", "÷", "^":
                if depth == 0 { last = c }
            default: break
            }
        }
        return last
    }

    // MARK: - public entry points

    /// The cheap structural probe: does ANY phrase form (or the
    /// spaced-terminal conversion) match this line's word pattern with
    /// its keywords live? The probe never evaluates operands — a gate
    /// failure inside the STRICT outcome (`500 of 200` with a plain
    /// left operand) is reported as notPercent and falls through to
    /// the legacy routes, exactly as before r83.
    public static func percentShape(_ line: String, env: TypedEnv) -> Bool {
        if spacedTerminalPercent(line: line, env: env, context: .legacy) != nil { return true }
        guard let pcs = pieces(of: line), !pcs.isEmpty else { return false }
        for form in forms(env: env) {
            switch matchResult(form: form, pcs: pcs, env: env) {
            case .matched, .dangling:
                return true
            case .none:
                continue
            }
        }
        return false
    }

    /// The strict result: evaluate the matched form (or the spaced
    /// conversion) with real operand values. `table` overrides the
    /// environment projection for the operand evaluation (the token
    /// route passes its marker placeholder table).
    public static func percentOutcome(_ line: String, env: TypedEnv,
                                      context: NumberFormatContext,
                                      table: [String: TypedScalar]? = nil) -> Outcome {
        // The terminal conversion is checked first: it is the most
        // specific reading of a trailing ` %`.
        if let t = spacedTerminalPercent(line: line, env: env, context: context, table: table) {
            return t
        }
        guard let pcs = pieces(of: line), !pcs.isEmpty else { return .notPercent }
        var dangling = false
        for form in forms(env: env) {
            switch matchResult(form: form, pcs: pcs, env: env) {
            case .none:
                continue
            case .dangling:
                // A phrase missing its value operand fails safely —
                // it never degrades to the word-stripping fallback.
                dangling = true
                continue
            case .matched(let opsPieces):
                var ops: [OperandValue] = []
                for p in opsPieces {
                    // A word operand is a NAMED VALUE: keep the
                    // original case (the environment keys are display
                    // names).
                    let named: String? = p.isWord ? p.text : nil
                    guard let v = operandValue(p.text, named: named, env: env,
                                               context: context, table: table) else {
                        return .error("Invalid expression")
                    }
                    ops.append(v)
                }
                guard let r = form.eval(ops) else { return .notPercent }
                return .value(r)
            }
        }
        if dangling { return .error("Invalid expression") }
        return .notPercent
    }
}
