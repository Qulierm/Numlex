import Foundation
import NumlexCore

// MARK: - r82: conditions, comparisons and booleans
//
// One typed boolean layer, strict everywhere it touches:
//
// - A real `Bool` (never numeric 1/0): comparison and logical
//   expressions, boolean literals/variables, `if <c> then <a> else <b>`
//   and the conditional-assignment form `if c then x = a else x = b`
//   (same target in both branches; ONLY the selected branch evaluates
//   and mutates).
// - Strict typing: arithmetic/functions/percent and relational ordering
//   require scalars; `==`/`!=` allow scalar-scalar or bool-bool only;
//   logical/conditional operators require booleans; money, units and
//   dates NEVER coerce; chains like `1 < 2 < 3` error.
// - Lazy `and`/`or`/`if`: the unselected branch never evaluates, so it
//   cannot divide by zero or mutate anything.
// - Booleans stay OUT of the numeric world: no totals, no rounding, no
//   previous answer, and the legacy numeric `evaluateExpression` API
//   fails deterministically instead of coercing.
// - Formatting: canonical spaces around comparison/logical operators
//   (idempotent, caret maps intact); syntax roles: comparator glyphs
//   are operators, keywords/literals take the specifier role, boolean
//   names take the variable role; prose never becomes math.
// - Tokens: a boolean answer mints a DISTINCT boolean token (never a
//   0/1 Double) that shows its lowercase word, joins logical and
//   comparison expressions, feeds boolean assignments, and fails
//   strictly in arithmetic.

private let M = "\u{FFFC}"

/// One evaluated sheet through the same API the app uses.
private func r82Lines(_ content: String) -> [SheetLine] {
    var v: [String: Double] = [:]
    return evaluateSheet(content, variables: &v, rates: Rates(), decimalPlaces: 7)
}

private func r82IsBool(_ r: LineResult, _ b: Bool, _ what: String) throws {
    guard case .boolean(let v) = r else {
        throw CaseFailure(message: "\(what): expected boolean \(b), got \(r)",
                          location: "R82Cases")
    }
    try expectEqual(v, b, "\(what) value")
}

private func r82IsNumber(_ r: LineResult, _ v: Double, _ what: String) throws {
    guard case .number(let n, _, _, _) = r, n == v else {
        throw CaseFailure(message: "\(what): expected \(v), got \(r)",
                          location: "R82Cases")
    }
}

/// A scalar answer whether it renders as a plain number or a variable
/// assignment (single identifiers assign as `.variable`, conditional
/// value branches and multiword names alike).
private func r82IsScalar(_ r: LineResult, _ v: Double, _ what: String) throws {
    switch r {
    case .number(let n, nil, _, _) where n == v: return
    case .variable(_, let n, _, _) where n == v: return
    default:
        throw CaseFailure(message: "\(what): expected scalar \(v), got \(r)",
                          location: "R82Cases")
    }
}

private func r82IsError(_ r: LineResult, _ what: String) throws {
    guard case .error = r else {
        throw CaseFailure(message: "\(what): expected an error, got \(r)",
                          location: "R82Cases")
    }
}

public let r82Cases: [EngineCase] = [
    // MARK: Comparisons and literals

    EngineCase("r82-comparison-basics") {
        try r82IsBool(r82Lines("2 < 3")[0].result, true, "2 < 3")
        try r82IsBool(r82Lines("3 < 2")[0].result, false, "3 < 2")
        try r82IsBool(r82Lines("2 <= 2")[0].result, true, "2 <= 2")
        try r82IsBool(r82Lines("3 <= 2")[0].result, false, "3 <= 2")
        try r82IsBool(r82Lines("3 >= 4")[0].result, false, "3 >= 4")
        try r82IsBool(r82Lines("4 >= 4")[0].result, true, "4 >= 4")
        try r82IsBool(r82Lines("2 == 2")[0].result, true, "2 == 2")
        try r82IsBool(r82Lines("2 == 3")[0].result, false, "2 == 3")
        try r82IsBool(r82Lines("2 != 3")[0].result, true, "2 != 3")
        try r82IsBool(r82Lines("2 != 2")[0].result, false, "2 != 2")
    },

    EngineCase("r82-literals-case-insensitive") {
        try r82IsBool(r82Lines("true")[0].result, true, "true")
        try r82IsBool(r82Lines("FALSE")[0].result, false, "FALSE")
        try r82IsBool(r82Lines("True And FaLsE")[0].result, false, "mixed case and")
    },

    EngineCase("r82-logical-words-and-aliases") {
        try r82IsBool(r82Lines("true and false")[0].result, false, "and")
        try r82IsBool(r82Lines("true or false")[0].result, true, "or")
        try r82IsBool(r82Lines("not false")[0].result, true, "not")
        try r82IsBool(r82Lines("!true")[0].result, false, "! alias")
        try r82IsBool(r82Lines("true && false")[0].result, false, "&& alias")
        try r82IsBool(r82Lines("true || false")[0].result, true, "|| alias")
        try r82IsBool(r82Lines("!!false")[0].result, false, "double negation")
    },

    EngineCase("r82-short-circuit-laziness") {
        // The false side of `and` is never evaluated: no division by
        // zero surfaces, the line simply reports false.
        try r82IsBool(r82Lines("false && (1/0 > 0)")[0].result, false, "and short-circuit")
        try r82IsBool(r82Lines("true || (1/0 > 0)")[0].result, true, "or short-circuit")
        // A SELECTED branch that divides by zero is a real error.
        try r82IsError(r82Lines("true && (1/0 > 0)")[0].result, "selected and branch")
        try r82IsError(r82Lines("1/0 > 0")[0].result, "direct division")
    },

    EngineCase("r82-precedence") {
        // and binds tighter than or; not above and; comparisons below
        // arithmetic; equality below relational.
        try r82IsBool(r82Lines("true or true and false")[0].result, true, "or/and")
        try r82IsBool(r82Lines("not true and false")[0].result, false, "not/and")
        try r82IsBool(r82Lines("not (true and false)")[0].result, true, "parenthesized not")
        try r82IsBool(r82Lines("1 + 1 == 2")[0].result, true, "arith over equality")
        try r82IsBool(r82Lines("3 < 2 + 1")[0].result, false, "arith over relational")
        try r82IsBool(r82Lines("2 < 3 and 4 > 5")[0].result, false, "and of comparisons")
        // Chained comparisons are a type error, never silent truth.
        guard case .error = r82Lines("1 < 2 < 3")[0].result else {
            throw CaseFailure(message: "1 < 2 < 3 must error", location: "R82Cases")
        }
    },

    EngineCase("r82-equality-mixed-types-error") {
        try r82IsError(r82Lines("1 == true")[0].result, "1 == true")
        try r82IsError(r82Lines("1 != true")[0].result, "1 != true")
        try r82IsBool(r82Lines("true == true")[0].result, true, "bool equality")
        try r82IsBool(r82Lines("true != false")[0].result, true, "bool inequality")
        // Relational ordering with a boolean operand is a type error.
        try r82IsError(r82Lines("true < false")[0].result, "true < false")
    },

    EngineCase("r82-strict-typing-arith-functions-percent") {
        try r82IsError(r82Lines("true + 1")[0].result, "true + 1")
        try r82IsError(r82Lines("2 - true")[0].result, "2 - true")
        try r82IsError(r82Lines("true × 2")[0].result, "true × 2")
        try r82IsError(r82Lines("true ^ 2")[0].result, "true ^ 2")
        try r82IsError(r82Lines("true % 10")[0].result, "true % 10")
        try r82IsError(r82Lines("sqrt(true)")[0].result, "sqrt(true)")
        try r82IsError(r82Lines("true and 1")[0].result, "and with scalar")
        // r85: int AND/OR int is BITWISE — `1 and 2` = 0 (the exact
        // lane owns integer-shaped and/or lines; the mixed bool/int
        // case above stays a strict error).
        let andBits = r82Lines("1 and 2")[0].result
        guard case .integer(let v, let r) = andBits, v == 0, r == 10 else {
            throw CaseFailure(message: "1 and 2 = 0 (bitwise, r85), got \(andBits)")
        }
        // A conditional branch with a boolean VALUE is fine; a branch
        // with an unknown word is not.
        try r82IsError(r82Lines("if true then butter else 2")[0].result, "prose branch")
    },

    EngineCase("r82-money-unit-date-never-coerce") {
        // Money: a money name fails strictly in a boolean context.
        let money = r82Lines("apple = 5$\napple < 3")
        try r82IsError(money[1].result, "money < scalar")
        let money2 = r82Lines("apple = 5$\napple and true")
        try r82IsError(money2[1].result, "money and true")
        // Units: unit quantities are not scalars.
        try r82IsError(r82Lines("5 km < 3")[0].result, "unit < scalar")
        try r82IsError(r82Lines("3 < 5 km")[0].result, "scalar < unit")
        // Dates: date answers are not scalars.
        try r82IsError(r82Lines("tomorrow < 5")[0].result, "date < scalar")
    },

    EngineCase("r82-prose-never-becomes-math") {
        // Logical words in ordinary prose without any boolean syntax or
        // boolean name stay prose — never math, never an error.
        for prose in ["bread and butter", "fish & chips", "not bad",
                      "if you go then i come"] {
            let l = r82Lines(prose)[0].result
            guard case .skip = l else {
                throw CaseFailure(message: "prose must stay quiet: \(prose) -> \(l)",
                                  location: "R82Cases")
            }
        }
    },

    EngineCase("r82-conditional-value-form") {
        try r82IsScalar(r82Lines("if false then 1/0 else 42")[0].result, 42, "else branch")
        try r82IsScalar(r82Lines("if true then 42 else 1/0")[0].result, 42, "then branch")
        try r82IsError(r82Lines("if true then 1/0 else 42")[0].result, "selected 1/0")
        try r82IsScalar(r82Lines("if 2 < 3 then 1 else 0")[0].result, 1, "comparison condition")
        try r82IsBool(r82Lines("if true then true else false")[0].result, true, "boolean branches")
        // Conditional is the LOWEST precedence, right-associative.
        try r82IsScalar(r82Lines("if false then 1 else if true then 5 else 9")[0].result, 5, "nested else")
    },

    // MARK: Boolean assignments

    EngineCase("r82-boolean-assignment-identifier") {
        // Contract line: `flag = 2 < 3` then `flag and true`.
        let sheet = r82Lines("flag = 2 < 3\nflag and true")
        try r82IsBool(sheet[0].result, true, "flag = 2 < 3")
        try r82IsBool(sheet[1].result, true, "flag and true")
        let sheet2 = r82Lines("flag = 2 < 3\nflag or false\nnot flag")
        try r82IsBool(sheet2[1].result, true, "flag or false")
        try r82IsBool(sheet2[2].result, false, "not flag")
        // A boolean variable is not a number: arithmetic fails.
        let sheet3 = r82Lines("flag = 2 < 3\nflag + 1")
        try r82IsError(sheet3[1].result, "flag + 1")
        // Reassignment flips the type cleanly.
        let sheet4 = r82Lines("x = 5\nx = 2 < 3\nx and true")
        try r82IsScalar(sheet4[0].result, 5, "scalar first")
        try r82IsBool(sheet4[1].result, true, "boolean after")
        try r82IsBool(sheet4[2].result, true, "x and true")
    },

    EngineCase("r82-boolean-assignment-multiword") {
        let sheet = r82Lines("my flag = 3 >= 4 or 2 < 3\nmy flag")
        try r82IsBool(sheet[0].result, true, "multiword boolean RHS")
        try r82IsBool(sheet[1].result, true, "multiword reference")
        let sheet2 = r82Lines("my flag = 2 < 3\nmy flag and other or false\nother = 3 < 9")
        // `other` is used before it is declared: the line errors and the
        // name is not reserved, then the declaration follows.
        try r82IsError(sheet2[1].result, "forward reference")
        try r82IsBool(sheet2[2].result, true, "later declaration")
    },

    EngineCase("r82-conditional-assignment") {
        // Contract line: `if false then x = 1 else x = 2` then `x` => 2.
        let sheet = r82Lines("if false then x = 1 else x = 2\nx")
        try r82IsScalar(sheet[0].result, 2, "else branch assigned")
        try r82IsScalar(sheet[1].result, 2, "x reads the stored value")
        // The UNSELECTED branch never evaluates: its 1/0 cannot error.
        let sheet2 = r82Lines("if false then x = 1/0 else x = 2\nx")
        try r82IsScalar(sheet2[0].result, 2, "unselected 1/0 skipped")
        // ...but a SELECTED bad branch is a real error.
        try r82IsError(r82Lines("if true then x = 1/0 else x = 2")[0].result, "selected 1/0")
        // The unselected branch must not MUTATE: only the selected one
        // writes the environment — both directions, with values that
        // would be visible if the dead branch ran.
        let mut1 = r82Lines("y = 5\nif true then y = 5 else y = 7\ny")
        try r82IsScalar(mut1[2].result, 5, "dead else branch never wrote 7")
        let mut2 = r82Lines("y = 5\nif false then y = 9 else y = 5\ny")
        try r82IsScalar(mut2[2].result, 5, "dead then branch never wrote 9")
        // Both branches must name the SAME target.
        try r82IsError(r82Lines("if true then a = 1 else b = 2")[0].result, "different targets")
        // A boolean branch stores a real boolean.
        let sheet4 = r82Lines("if true then x = 2 < 3 else x = 3 < 2\nx and true")
        try r82IsBool(sheet4[0].result, true, "boolean branch")
        try r82IsBool(sheet4[1].result, true, "x and true after conditional")
    },

    EngineCase("r82-assignment-then-conditional-line") {
        // `x = if …` is a plain assignment whose RHS is a conditional.
        let sheet = r82Lines("x = if 2 < 3 then 10 else 20\nx")
        try r82IsScalar(sheet[0].result, 10, "x = if …")
        try r82IsScalar(sheet[1].result, 10, "x")
        let sheet2 = r82Lines("x = if false then true else false\nx or true")
        try r82IsBool(sheet2[0].result, false, "boolean conditional RHS")
        try r82IsBool(sheet2[1].result, true, "x or true")
    },

    EngineCase("r82-keyword-compatibility") {
        // A sheet that historically used a keyword-like identifier keeps
        // it as a variable: the grammar yields to the active name.
        let sheet = r82Lines("and = 5\nand")
        try r82IsScalar(sheet[0].result, 5, "and = 5")
        try r82IsNumber(sheet[1].result, 5, "and is the variable")
        let sheet2 = r82Lines("true = 7\ntrue")
        try r82IsScalar(sheet2[0].result, 7, "true = 7")
        try r82IsNumber(sheet2[1].result, 7, "true is the variable")
        // …and a comparison still works while the variable exists.
        let sheet3 = r82Lines("and = 5\n2 < 3")
        try r82IsBool(sheet3[1].result, true, "comparisons unaffected")
    },

    // MARK: Numeric-world exclusions

    EngineCase("r82-totals-exclude-booleans") {
        // The section total sums ordinary rows only: the boolean line
        // contributes nothing.
        let sheet = r82Lines("1\n2 < 3\n3\ntotal")
        try r82IsNumber(sheet[3].result, 4, "total skips the boolean row")
        // A section of ONLY boolean rows totals to 0 (no contributions),
        // never an error and never a 1/0 coercion.
        let sheet2 = r82Lines("2 < 3\n3 < 2\ntotal")
        try r82IsNumber(sheet2[2].result, 0, "boolean-only section")
    },

    EngineCase("r82-previous-answer-excludes-booleans") {
        // A boolean answer is never the source of the previous-answer
        // chain (it could not feed `ans + 1`).
        let ids = (0..<3).map { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0))! }
        let boolSheet = PreviousAnswerPlan.plan(
            content: "2 < 3\n\n",
            lineIDs: ids, caret: 7, op: "+")
        try expectEqual(boolSheet, nil, "boolean source is not answerable")
        let numSheet = PreviousAnswerPlan.plan(
            content: "2 + 2\n\n",
            lineIDs: ids, caret: 7, op: "+")
        try expect(numSheet != nil, "numeric source stays answerable",
                   "the numeric chain is untouched")
    },

    EngineCase("r82-rounding-and-clipboard-booleans") {
        // Booleans offer Copy Answer + Delete Line only — never the
        // rounding submenu — and copy their lowercase word.
        let menu = AnswerDisplay.menu(for: .boolean(value: true))
        try expectEqual(menu?.showsActions, true, "copy/delete offered")
        try expectEqual(menu?.showsRounding, false, "no rounding on booleans")
        try expectEqual(AnswerDisplay.text(for: .boolean(value: true),
                                           decimalPlaces: 7, context: .legacy),
                        "true", "true copies as true")
        try expectEqual(AnswerDisplay.text(for: .boolean(value: false),
                                           decimalPlaces: 7, context: .legacy),
                        "false", "false copies as false")
        // Regional formatting never touches boolean words.
        let we = NumberFormatContext.resolve(
            RegionalNumberPreferences(region: .westernEurope,
                                      convertForeignOnPaste: false,
                                      showThousandsSeparator: true,
                                      useCompactNotation: false),
            locale: Locale(identifier: "de_DE"))
        try expectEqual(AnswerDisplay.text(for: .boolean(value: true),
                                           decimalPlaces: 7, context: we),
                        "true", "decimal-comma mode keeps the word")
    },

    EngineCase("r82-legacy-numeric-api-fails-deterministically") {
        // The old public numeric API keeps its signature and fails on
        // boolean-shaped input instead of coercing.
        var threw = false
        do { _ = try evaluateExpression("2 < 3", variables: [:]) }
        catch { threw = true }
        try expect(threw, "numeric entry rejects boolean expressions")
        threw = false
        do { _ = try evaluateExpression("true and false", variables: [:]) }
        catch { threw = true }
        try expect(threw, "numeric entry rejects logical expressions")
        // …and still evaluates plain numbers.
        try expectEqual(try evaluateExpression("2 + 2", variables: [:]), 4, "numbers fine")
    },

    // MARK: Boolean tokens

    EngineCase("r82-token-bare-boolean") {
        let u0 = UUID(), u1 = UUID()
        let content = "2 < 3\n" + M
        let (lines, tokens) = resolveSheet(content: content, lineIDs: [u0, u1],
                                           references: [AnswerReference(sourceLineID: u0, labelLine: 1, location: 6)],
                                           rates: Rates(), decimalPlaces: 7)
        try r82IsBool(lines[1].result, true, "bare boolean token")
        try expectEqual(tokens[0].state,
                        .activeBool(value: true, display: "true"),
                        "distinct boolean token state")
    },

    EngineCase("r82-token-logical-expressions") {
        let u0 = UUID()
        func mk(source: String,
               tokenLines: [String]) -> (lines: [SheetLine], tokens: [TokenResolution]) {
            var ids = [u0]
            var refs: [AnswerReference] = []
            var content = source + "\n"
            for tl in tokenLines {
                let lineID = UUID()
                ids.append(lineID)
                // The marker sits at the start of each token line: its
                // document offset is the content length just before the
                // line.
                let pos = (content as NSString).length
                content += tl.replacingOccurrences(of: "\u{0001}", with: M) + "\n"
                refs.append(AnswerReference(sourceLineID: u0, labelLine: 1, location: pos))
            }
            return resolveSheet(content: content, lineIDs: ids, references: refs,
                                rates: Rates(), decimalPlaces: 7)
        }
        // `M and true` / `M and false` / `M or false` against `2 < 3`.
        let t = mk(source: "2 < 3", tokenLines: ["\u{0001} and true", "\u{0001} and false"])
        try r82IsBool(t.lines[1].result, true, "M and true")
        try r82IsBool(t.lines[2].result, false, "M and false")
        let t2 = mk(source: "3 < 2", tokenLines: ["\u{0001} or true"])
        try r82IsBool(t2.lines[1].result, true, "false token or true")
        // Comparison against a boolean token: bool-bool equality works,
        // relational ordering on a boolean fails.
        let t3 = mk(source: "2 < 3", tokenLines: ["\u{0001} == true", "\u{0001} < 2"])
        try r82IsBool(t3.lines[1].result, true, "M == true")
        try r82IsError(t3.lines[2].result, "M < 2 (relational needs scalars)")
    },

    EngineCase("r82-token-arithmetic-fails") {
        let u0 = UUID()
        let content = "2 < 3\n" + M + " + 1\n" + M + " × 2"
        var ids = [u0]
        ids.append(UUID())
        ids.append(UUID())
        let refs = [
            AnswerReference(sourceLineID: u0, labelLine: 1, location: 6),
            AnswerReference(sourceLineID: u0, labelLine: 1, location: 12),
        ]
        let (lines, _) = resolveSheet(content: content, lineIDs: ids,
                                      references: refs, rates: Rates(), decimalPlaces: 7)
        try r82IsError(lines[1].result, "M + 1 on a boolean token")
        try r82IsError(lines[2].result, "M × 2 on a boolean token")
    },

    EngineCase("r82-token-conditional-and-assignment") {
        let u0 = UUID()
        var ids = [u0, UUID(), UUID(), UUID()]
        let content = "2 < 3\nif " + M + " then 1 else 0\nx = " + M + " and true\nx"
        let refs = [
            AnswerReference(sourceLineID: u0, labelLine: 1, location: 9),
            AnswerReference(sourceLineID: u0, labelLine: 1, location: 29),
        ]
        let (lines, _) = resolveSheet(content: content, lineIDs: ids,
                                      references: refs, rates: Rates(), decimalPlaces: 7)
        try r82IsScalar(lines[1].result, 1, "if M then 1 else 0")
        try r82IsBool(lines[2].result, true, "x = M and true")
        try r82IsBool(lines[3].result, true, "x is a real boolean")
    },

    EngineCase("r82-token-scalar-in-comparison") {
        // A SCALAR token joins comparisons as a plain number — the
        // legacy quantity route is untouched for non-boolean lines.
        let u0 = UUID()
        var ids = [u0, UUID()]
        let content = "2 + 2\n" + M + " < 5"
        let refs = [AnswerReference(sourceLineID: u0, labelLine: 1, location: 6)]
        let (lines, tokens) = resolveSheet(content: content, lineIDs: ids,
                                           references: refs, rates: Rates(), decimalPlaces: 7)
        try r82IsBool(lines[1].result, true, "M < 5 with M = 4")
        try expectEqual(tokens[0].state, .active(value: 4, unit: nil, display: "4"),
                        "scalar token state unchanged")
    },

    EngineCase("r82-token-money-never-coerces") {
        let u0 = UUID()
        var ids = [u0, UUID()]
        let content = "apple = 5$\n" + M + " and true"
        let refs = [AnswerReference(sourceLineID: u0, labelLine: 1, location: 12)]
        let (lines, _) = resolveSheet(content: content, lineIDs: ids,
                                      references: refs, rates: Rates(), decimalPlaces: 7)
        try r82IsError(lines[1].result, "money token in a boolean line")
    },

    // MARK: Formatting, caret maps, syntax roles

    EngineCase("r82-canonical-boolean-spacing") {
        // Canonical spacing around the new operators — idempotent.
        let pairs: [(String, String)] = [
            ("2<3", "2 < 3"),
            ("2 <3", "2 < 3"),
            ("a<=b", "a <= b"),
            ("a>= b", "a >= b"),
            ("a==b", "a == b"),
            ("a != b", "a != b"),
            ("a&&b", "a && b"),
            ("a||b", "a || b"),
            ("!x", "!x"),
        ]
        for (input, want) in pairs {
            let once = NotebookFormatting.canonicalMathText(input)
            try expectEqual(once, want, "canonical form of \(input)")
            let twice = NotebookFormatting.canonicalMathText(once)
            try expectEqual(twice, once, "idempotent on \(input)")
        }
    },

    EngineCase("r82-canonical-caret-map") {
        // The insertion-point map keeps working when spaces are added
        // around comparison operators (non-space order preserved).
        let map = NotebookFormatting.insertionMap(from: "2<3", to: "2 < 3")
        try expectEqual(map, [0, 1, 3, 5], "caret map 2<3 -> 2 < 3")
        let map2 = NotebookFormatting.insertionMap(from: "a==b", to: "a == b")
        try expectEqual(map2, [0, 1, 3, 4, 6], "caret map a==b -> a == b")
        // A line already canonical maps to itself.
        let map3 = NotebookFormatting.insertionMap(from: "2 < 3", to: "2 < 3")
        try expectEqual(map3, [0, 1, 1, 3, 3, 5], "stable line maps to itself")
    },

    EngineCase("r82-canonical-document-roundtrip") {
        // Canonicalizing a sheet with boolean lines keeps every line
        // evaluating to the identical result (canonical == input for
        // boolean math, unlike star replacement on numeric lines).
        let source = "2<3\nflag = 2<=3\nflag && true\nif flag then 1 else 0"
        var v: [String: Double] = [:]
        let before = evaluateSheet(source, variables: &v, rates: Rates(), decimalPlaces: 7)
        let canon = NotebookFormatting.canonicalDocument(source)
        var w: [String: Double] = [:]
        let after = evaluateSheet(canon, variables: &w, rates: Rates(), decimalPlaces: 7)
        try expectEqual(before.count, after.count, "same line count")
        for (i, (b, a)) in zip(before, after).enumerated() {
            try expectEqual(b.result, a.result, "line \(i + 1) result survives canonicalization")
        }
    },

    EngineCase("r82-syntax-roles-boolean") {
        // Comparator glyphs: operator role. `true`/`false`/`and`/`or`/
        // `not`/`if`/`then`/`else`: the existing specifier role.
        let cmp = SyntaxClassifier.spans(for: "2 < 3", rates: Rates(), decimalPlaces: 7)[0]
        try expectEqual(cmp.filter { $0.role == .operatorGlyph }.map { $0.range },
                        [NSRange(location: 2, length: 1)], "comparison glyph is an operator")
        try expectEqual(cmp.filter { $0.role == .number }.count, 2, "both literals are numbers")
        let logic = SyntaxClassifier.spans(for: "true and false", rates: Rates(), decimalPlaces: 7)[0]
        try expectEqual(logic.filter { $0.role == .specifier }.map { $0.range },
                        [NSRange(location: 0, length: 4),
                         NSRange(location: 5, length: 3),
                         NSRange(location: 9, length: 5)],
                        "keywords/literals take the specifier role")
        // A declared BOOLEAN name takes the variable role — through the
        // same shared matcher the evaluator uses.
        let named = SyntaxClassifier.spans(for: "flag = 2 < 3\nflag and true",
                                           rates: Rates(), decimalPlaces: 7)
        let lhsSpans = named[0].filter { $0.role == .variable }.map { $0.range }
        try expectEqual(lhsSpans, [NSRange(location: 0, length: 4)], "boolean LHS is a variable")
        let refSpans = named[1].filter { $0.role == .variable }.map { $0.range }
        try expectEqual(refSpans, [NSRange(location: 0, length: 4)], "boolean name reference")
        // A conditional VALUE line (`if c then 1 else 0`) evaluates to a
        // number but is boolean SYNTAX: the classifier must give it the
        // boolean palette (keyword specifiers + numbers), never the
        // lexical expression palette that would leave the keywords in
        // the base role.
        let condValue = SyntaxClassifier.spans(for: "if false then 1/0 else 42",
                                               rates: Rates(), decimalPlaces: 7)[0]
        let condSpec = condValue.filter { $0.role == .specifier }.map { $0.range }
        try expectEqual(condSpec,
                        [NSRange(location: 0, length: 2),
                         NSRange(location: 3, length: 5),
                         NSRange(location: 9, length: 4),
                         NSRange(location: 18, length: 4)],
                        "conditional value line keeps keyword specifiers")
        try expectEqual(condValue.filter { $0.role == .number }.count, 3,
                        "conditional value line keeps number spans")
        try expectEqual(condValue.filter { $0.role == .operatorGlyph }.count, 1,
                        "the slash stays an operator glyph")
        // Prose never gains boolean roles.
        let prose = SyntaxClassifier.spans(for: "bread and butter", rates: Rates(), decimalPlaces: 7)[0]
        try expectEqual(prose, [], "prose stays plain")
    },

    EngineCase("r82-assignment-recognition-never-matches-comparisons") {
        // The centralized `=` recognizer: `==`, `!=`, `<=`, `>=` never
        // enter any assignment route, so a comparison line never
        // declares a variable or looks like a natural assignment. An
        // unknown `x` makes the comparison a strict error — but NOT an
        // assignment: `x` stays undeclared.
        let sheet = r82Lines("x == 5\nx")
        try r82IsError(sheet[0].result, "x == 5 is a strict comparison")
        // `x` was never declared by that line: the follow-up `x` is
        // not a number/variable (it stays prose or errors — either
        // way, NOT an assignment).
        if case .number = sheet[1].result {
            throw CaseFailure(message: "x must not be declared by a comparison",
                              location: "R82Cases")
        }
        if case .variable = sheet[1].result {
            throw CaseFailure(message: "x must not be declared by a comparison",
                              location: "R82Cases")
        }
        // With a declared `x` the same comparison evaluates to a real
        // boolean — still with no assignment side effect.
        let decl = r82Lines("x = 5\nx == 5")
        try r82IsBool(decl[1].result, true, "declared comparison")
        // A comparison line is mathematical (it evaluates), and the
        // natural-shape probe stays false for it.
        try expectEqual(NotebookFormatting.isMathematical("x == 5",
                                                          rates: Rates(), decimalPlaces: 7),
                        true, "comparison lines are mathematical")
        try expectEqual(NotebookFormatting.isNaturalShape("x == 5", env: TypedEnv()),
                        false, "comparison is never a natural assignment")
    },
]
