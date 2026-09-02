import Foundation
import NumlexCore

/// r47: built-in math functions. Coverage:
/// 1. The ONE central registry: names, arities, case-insensitive lookup,
///    deterministic finite-Double semantics and domain errors.
/// 2. The shared parser: call position, precedence composition, nesting,
///    strict function-shaped input (no paren fallback), the shared comma
///    convention, precise syntax errors.
/// 3. Every scalar pipeline: free lines, assignments, variables,
///    multiword/global constants, natural/money rejection, unit
///    rejection, same-named builtin-vs-variable precedence.
/// 4. Unitless token route: shared-engine routing, multiple markers as
///    arguments, money/unit arguments rejected, legacy routes unchanged.
/// 5. Presentation: builtin call heads stay base text; canonical and
///    input grouping preserve argument separators and stay idempotent.

private let r47M = "\u{FFFC}"

private func evalE(_ s: String, vars: [String: Double] = [:]) throws -> Double {
    try evaluateExpression(s, variables: vars)
}

private func evalMsg(_ s: String, vars: [String: Double] = [:]) -> String? {
    do {
        _ = try evaluateExpression(s, variables: vars)
        return nil
    } catch {
        return (error as? LocalizedError)?.errorDescription
    }
}

private func lineResults(_ content: String,
                         constants: [UserConstant] = [],
                         decimalPlaces: Int = 2) -> [LineResult] {
    let lines = content.components(separatedBy: "\n")
    let r = resolveSheet(content: content,
                         lineIDs: lines.map { _ in UUID() },
                         references: [],
                         rates: Rates(),
                         decimalPlaces: decimalPlaces,
                         constants: constants)
    return r.lines.map(\.result)
}

private func num(_ r: LineResult) -> Double? {
    if case .number(let v, let u) = r { return u == nil ? v : nil }
    return nil
}

private func isErr(_ r: LineResult) -> Bool {
    if case .error = r { return true }
    return false
}

public let r47Cases: [EngineCase] = [
    // MARK: 1. Central registry

    EngineCase("r47-registry-table") {
        try expectEqual(MathFunctions.knownNames.count, 19, "19 builtins")
        for name in ["sqrt", "abs", "round", "min", "max", "sum", "average",
                     "pow", "ln", "log", "log10", "sin", "cos", "tan",
                     "asin", "acos", "atan", "radians", "degrees"] {
            try expect(MathFunctions.isKnown(name), "known: \(name)")
        }
        try expect(!MathFunctions.isKnown("sqr"), "sqr unknown")
        try expect(!MathFunctions.isKnown("exp"), "exp unknown")
        try expect(MathFunctions.isKnown("SQRT"), "case-insensitive known")
        try expectEqual(MathFunctions.arity("pow")?.min, 2, "pow min arity")
        try expectEqual(MathFunctions.arity("sum")?.max, Int.max, "sum variadic")
        try expectEqual(MathFunctions.arity("round")?.max, 2, "round max arity")
    },

    EngineCase("r47-registry-sqrt-abs-round") {
        try expectEqual(try MathFunctions.evaluate("sqrt", args: [9]), 3, "sqrt 9")
        try expectEqual(try MathFunctions.evaluate("sqrt", args: [0]), 0, "sqrt 0")
        try expectEqual(try MathFunctions.evaluate("abs", args: [-2.5]), 2.5, "abs -2.5")
        try expectEqual(try MathFunctions.evaluate("round", args: [2.5]), 3, "ties away from zero")
        try expectEqual(try MathFunctions.evaluate("round", args: [-2.5]), -3, "ties away (negative)")
        try expectEqual(try MathFunctions.evaluate("round", args: [1.234]), 1, "round to 0 dp")
        try expectEqual(try MathFunctions.evaluate("round", args: [1.234, 2]), 1.23, "round 2 dp")
        try expectEqual(try MathFunctions.evaluate("round", args: [1.25, 1]), 1.3, "round 1 dp")
        try expectEqual(try MathFunctions.evaluate("round", args: [123.456, -2]), 100, "negative digits")
        try expect(evalMsg2("round", [1, 2.5]) != nil, "non-integer digits domain")
        try expect(evalMsg2("round", [1, 16]) != nil, "digits out of -15...15")
    },

    EngineCase("r47-registry-min-max-sum-average") {
        try expectEqual(try MathFunctions.evaluate("min", args: [3, 1, 2]), 1, "min")
        try expectEqual(try MathFunctions.evaluate("max", args: [2, 9]), 9, "max")
        try expectEqual(try MathFunctions.evaluate("sum", args: [1, 2, 3]), 6, "sum")
        try expectEqual(try MathFunctions.evaluate("sum", args: [4.5]), 4.5, "sum one arg")
        try expectEqual(try MathFunctions.evaluate("average", args: [1, 2, 3]), 2, "average")
        try expectEqual(try MathFunctions.evaluate("average", args: [1, 2]), 1.5, "average even")
    },

    EngineCase("r47-registry-stable-average") {
        // A naive sum overflows (inf); the mean is finite and exact.
        try expectEqual(try MathFunctions.evaluate("average", args: [1e308, 1e308]), 1e308,
                        "finite mean where the naive sum overflows")
        try expectEqual(try MathFunctions.evaluate("average", args: [1e308, 5e307]), 7.5e307,
                        "shifted partial mean")
        try expectEqual(try MathFunctions.evaluate("average", args: [1e308, -1e308]), 0,
                        "opposite extremes")
    },

    EngineCase("r47-registry-pow") {
        try expectEqual(try MathFunctions.evaluate("pow", args: [2, 10]), 1024, "pow")
        try expectEqual(try MathFunctions.evaluate("pow", args: [9, 0.5]), 3, "sqrt via pow")
        try expectEqual(try MathFunctions.evaluate("pow", args: [0.5, -2]), 4, "negative exponent")
        try expectEqual(try MathFunctions.evaluate("pow", args: [5, 0]), 1, "zero exponent")
        try expect(evalMsg2("pow", [10, 400]) != nil, "pow overflow rejected")
    },

    EngineCase("r47-registry-log-ln") {
        try expectEqual(try MathFunctions.evaluate("ln", args: [1]), 0, "ln 1")
        let lne = try MathFunctions.evaluate("ln", args: [exp(1.0)])
        try expect(abs(lne - 1) < 1e-15, "ln e")
        try expectEqual(try MathFunctions.evaluate("log", args: [100]), 2, "log = log10")
        let l8 = try MathFunctions.evaluate("log", args: [8, 2])
        try expect(abs(l8 - 3) < 1e-12, "log base 2")
        let l10 = try MathFunctions.evaluate("log", args: [1000, 10])
        try expect(abs(l10 - 3) < 1e-12, "log base 10")
        try expectEqual(try MathFunctions.evaluate("log10", args: [1000]), 3, "log10")
        try expect(evalMsg2("ln", [0]) != nil, "ln 0 domain")
        try expect(evalMsg2("ln", [-1]) != nil, "ln -1 domain")
        try expect(evalMsg2("log", [0, 2]) != nil, "log 0 domain")
        try expect(evalMsg2("log", [8, 1]) != nil, "log base 1 domain")
        try expect(evalMsg2("log", [8, -2]) != nil, "log negative base domain")
    },

    EngineCase("r47-registry-trig") {
        try expectEqual(try MathFunctions.evaluate("sin", args: [0]), 0, "sin 0")
        try expectEqual(try MathFunctions.evaluate("cos", args: [0]), 1, "cos 0")
        try expectEqual(try MathFunctions.evaluate("tan", args: [0]), 0, "tan 0")
        try expectEqual(try MathFunctions.evaluate("sin", args: [Double.pi / 2]), 1, "sin pi/2")
        let r90 = try MathFunctions.evaluate("radians", args: [90])
        let s90 = try MathFunctions.evaluate("sin", args: [r90])
        try expect(abs(s90 - 1) < 1e-12, "sin radians(90)")
        let r60 = try MathFunctions.evaluate("radians", args: [60])
        let c60 = try MathFunctions.evaluate("cos", args: [r60])
        try expect(abs(c60 - 0.5) < 1e-12, "cos radians(60)")
        let a30 = try MathFunctions.evaluate("asin", args: [0.5])
        let t30 = try MathFunctions.evaluate("radians", args: [30])
        try expect(abs(a30 - t30) < 1e-12, "asin 0.5 = 30deg")
        let a1 = try MathFunctions.evaluate("atan", args: [1])
        let r45 = try MathFunctions.evaluate("radians", args: [45])
        try expect(abs(a1 - r45) < 1e-12, "atan 1 = 45deg")
        let d = try MathFunctions.evaluate("degrees", args: [Double.pi])
        try expect(abs(d - 180) < 1e-9, "degrees(pi) = 180")
        try expect(evalMsg2("asin", [2]) != nil, "asin 2 domain")
        try expect(evalMsg2("acos", [-2]) != nil, "acos -2 domain")
    },

    EngineCase("r47-registry-arity-domain-errors") {
        func err(_ name: String, _ args: [Double]) -> String? {
            do { _ = try MathFunctions.evaluate(name, args: args); return nil }
            catch { return (error as? LocalizedError)?.errorDescription }
        }
        let m1 = err("sqrt", [1, 2])
        try expect(m1?.contains("sqrt expects exactly 1 argument") == true, "arity message: \(m1 ?? "nil")")
        let m2 = err("sum", [])
        try expect(m2?.contains("at least 1") == true, "variadic arity message")
        let m3 = err("sqrt", [-1])
        try expect(m3?.contains("sqrt:") == true, "domain message")
        let m4 = err("pow", [10, 400])
        try expect(m4?.contains("not finite") == true, "non-finite message")
    },

    // MARK: 2. Shared parser

    EngineCase("r47-parser-precedence") {
        try expectEqual(try evalE("sqrt(9) + 1"), 4, "call + literal")
        try expectEqual(try evalE("2 × sqrt(9)"), 6, "literal × call")
        try expectEqual(try evalE("sqrt(9) × 2"), 6, "call × literal")
        try expectEqual(try evalE("-sqrt(9)"), -3, "unary sign over call")
        try expectEqual(try evalE("sqrt(9)^2"), 9, "call as power base")
        try expectEqual(try evalE("2^sqrt(16)"), 16, "call as power exponent")
        try expectEqual(try evalE("(2 + 1)^2"), 9, "plain parens unchanged")
        try expectEqual(try evalE("20% of sqrt(100)"), 2, "of with call (0.2 × 10)")
        try expectEqual(try evalE("10% of 50% of 200"), 10, "legacy of chain unchanged")
    },

    EngineCase("r47-parser-nesting-and-args") {
        try expectEqual(try evalE("sqrt(sqrt(16))"), 2, "nested calls")
        try expectEqual(try evalE("sqrt(1 + 3)"), 2, "expression argument")
        try expectEqual(try evalE("min(max(1, 2), 3)"), 2, "nested min/max")
        try expectEqual(try evalE("sum(1 + 1, 2 × 3)"), 8, "arithmetic args")
        try expectEqual(try evalE("round(abs(-2.5))"), 3, "round(abs())")
        try expectEqual(try evalE("sqrt(2) × PI", vars: ["PI": 3.14159265]),
                        sqrt(2) * 3.14159265, "call with variable arg")
        try expectEqual(try evalE("x + sqrt(9)", vars: ["x": 1]), 4, "call next to variable")
    },

    EngineCase("r47-parser-case-insensitive") {
        try expectEqual(try evalE("SQRT(9)"), 3, "uppercase name")
        try expectEqual(try evalE("Min(3, 2)"), 2, "mixed-case name")
        try expectEqual(try evalE("SUM(1,2)"), 3, "upper SUM")
        let lnE = try evalE("Ln(2.718281828459045)")
        try expect(abs(lnE - 1) < 1e-15, "Ln")
    },

    EngineCase("r47-parser-strict-unknown") {
        try expectEqual(evalMsg("sqr(9)"), "Unknown function 'sqr'", "unknown function exact")
        try expectEqual(evalMsg("foo(1, 2)"), "Unknown function 'foo'", "unknown arity 2")
        // A function-shaped input is NEVER a parenthesized operand.
        let r = lineResults("sqr(9)")
        try expect(isErr(r[0]), "free unknown call is an error, not (9)")
    },

    EngineCase("r47-parser-comma-syntax") {
        try expectEqual(evalMsg("sqrt()"), "sqrt() takes at least 1 argument", "empty args")
        try expectEqual(evalMsg("sum(1,)"), "Trailing comma in function arguments", "trailing comma")
        try expectEqual(evalMsg("sum(1,,2)"), "Unexpected comma in function arguments", "double comma")
        try expectEqual(evalMsg("sum(,1)"), "Unexpected comma in function arguments", "leading comma")
        try expectEqual(evalMsg("sum(1 2)"), "Missing comma between function arguments", "missing comma")
        try expectEqual(evalMsg("sqrt(9"), "Missing closing parenthesis", "missing close")
        try expectEqual(evalMsg("sqrt(1, 2)"), "sqrt expects exactly 1 argument (got 2)", "arity over")
        try expectEqual(evalMsg("pow(2)"), "pow expects exactly 2 arguments (got 1)", "arity under")
        try expectEqual(evalMsg("round(1, 2, 3)"), "round expects 1 ... 2 arguments (got 3)", "bounded arity")
    },

    EngineCase("r47-parser-comma-grouping-convention") {
        // The shared comma rule: a comma is grouping only when the run
        // after it is EXACTLY three digits; the space is the separator
        // disambiguator.
        try expectEqual(try evalE("sum(1,234)"), 1234, "sum(1,234) = one grouped literal 1234")
        try expectEqual(try evalE("sum(1, 234)"), 235, "space makes two args")
        try expectEqual(try evalE("sum(1,2,3)"), 6, "three args")
        try expectEqual(try evalE("sum(12, 345)"), 357, "12 and 345")
        try expectEqual(try evalE("sum(12,345)"), 12345, "12,345 is one literal")
        try expectEqual(try evalE("sum(1,2345)"), 2346, "4 digits after comma = separate arg")
        // Legacy free-line behavior is byte-for-byte unchanged.
        try expectEqual(try evalE("1,234"), 1234, "free grouped number")
        try expectEqual(try evalE("1,234,567"), 1234567, "chained free grouping")
        try expectEqual(try evalE("1,234 + 1"), 1235, "free grouping + arithmetic")
    },

    EngineCase("r47-parser-domain-through-parser") {
        let m1 = evalMsg("sqrt(-1)")
        try expect(m1?.contains("sqrt:") == true, "domain message propagates: \(m1 ?? "nil")")
        try expect(evalMsg("ln(0)") != nil, "ln 0 through parser")
        try expect(evalMsg("asin(2)") != nil, "asin 2 through parser")
        try expect(evalMsg("10% of sqrt(-4)") != nil, "domain inside of chain")
    },

    // MARK: 3. Scalar pipelines

    EngineCase("r47-lines-free-and-assignment") {
        let r = lineResults("sqrt(9)\nx = sqrt(9)\nx × 2\ny = sum(1, 2) + x")
        try expectEqual(num(r[0]), 3, "free function line")
        try expect(r[1] == .variable(name: "x", value: 3), "assignment to function")
        try expectEqual(num(r[2]), 6, "variable after assignment")
        try expect(r[3] == .variable(name: "y", value: 6), "chained assignment")
    },

    EngineCase("r47-lines-strict-assignment") {
        let r = lineResults("x = sqr(9)\nx")
        try expect(isErr(r[0]), "assignment to unknown function errors")
        // The environment is untouched: `x` is still undefined prose.
        try expect(isErr(r[1]) || r[1] == .skip, "no env mutation from failed call")
        // The precise message is visible on the assignment route.
        let m1 = lineResults("x = sqr(9)")
        if case .error(let m) = m1[0] {
            try expectEqual(m, "Unknown function 'sqr'", "precise assignment message")
        } else {
            throw CaseFailure(message: "expected error, got \(m1[0])")
        }
    },

    EngineCase("r47-lines-constants-as-arguments") {
        let constants = [
            UserConstant(name: "VAT Rate", expression: "0.21"),
            UserConstant(name: "Side", expression: "sqrt(4)"),
            UserConstant(name: "Bad", expression: "sqr(9)"),
        ]
        let r = lineResults("round(VAT Rate × 100)\nsum(VAT Rate, 0.79)\n(1 + Side) × 2",
                            constants: constants)
        try expectEqual(num(r[0]), 21, "constant through a call")
        try expectEqual(num(r[1]), 1, "two constants as args")
        try expectEqual(num(r[2]), 6, "constant with a function expression")
        let rows = ConstantResolver.resolve(constants).rows
        try expectEqual(rows[1].status, .valid(.scalar(2)), "Side resolves to sqrt(4)")
        try expectEqual(rows[2].status, .invalidDependency, "Bad constant stays inactive")
    },

    EngineCase("r47-lines-builtin-vs-same-name") {
        // A variable named like a builtin stays a variable in non-call
        // position; the builtin wins ONLY at the call head.
        let r = lineResults("sum = 5\nmin = 9\nsum + 1\nmin + 1\nsum(1, 2)\nmin(1, 2)")
        try expect(r[0] == .variable(name: "sum", value: 5), "assign to 'sum'")
        try expect(r[1] == .variable(name: "min", value: 9), "assign to 'min'")
        try expectEqual(num(r[2]), 6, "variable sum in non-call position")
        try expectEqual(num(r[3]), 10, "variable min in non-call position")
        try expectEqual(num(r[4]), 3, "builtin wins at the call head")
        try expectEqual(num(r[5]), 1, "builtin wins at the call head (min)")
    },

    EngineCase("r47-lines-money-rejects-calls") {
        // A currency marker on a line with a call: hidden generic error,
        // no currency-through-function result.
        let r1 = lineResults("sqrt($100)")
        try expect(isErr(r1[0]), "sqrt($100) hidden error")
        let r2 = lineResults("monthly rent = $2400\nsqrt(monthly rent)")
        try expect(isErr(r2[1]), "call over a compound money name errors")
        // Legacy money lines are untouched.
        let r3 = lineResults("lunch was $55 + 25% tip")
        try expectEqual(r3[0], .money(value: 68.75, code: "USD"), "legacy money line unchanged")
    },

    EngineCase("r47-lines-units-strict-in-calls") {
        // Unit-bearing arguments to a function are strict syntax errors
        // — never a silent word-stripped scalar.
        let r1 = lineResults("sqrt(10 km)")
        try expect(isErr(r1[0]), "unit inside a call errors")
        let r2 = lineResults("min(2 kg, 3 kg)")
        try expect(isErr(r2[0]), "unit args error")
        // The legacy unit conversion route is untouched.
        let r3 = lineResults("10 km to m")
        if case .number(let v, let u) = r3[0] {
            try expectEqual(v, 10000, "conversion value unchanged")
            try expectEqual(u, "m", "conversion unit unchanged")
        } else {
            throw CaseFailure(message: "expected conversion, got \(r3[0])")
        }
    },

    // MARK: 4. Unitless token route

    EngineCase("r47-token-unitless-functions") {
        let u0 = UUID(), u1 = UUID(), u2 = UUID(), u3 = UUID()
        let content = "720\nsqrt(" + r47M + ")\nsum(" + r47M + ", 1, 2)\n" + r47M + " ^ 2"
        let refs = [
            AnswerReference(sourceLineID: u0, labelLine: 1, location: 9),
            AnswerReference(sourceLineID: u0, labelLine: 1, location: 16),
            AnswerReference(sourceLineID: u0, labelLine: 1, location: 25),
        ]
        let r = resolveSheet(content: content, lineIDs: [u0, u1, u2, u3],
                             references: refs, rates: Rates(), decimalPlaces: 2)
        try expectEqual(num(r.lines[1].result), 26.83, "sqrt of a token")
        try expectEqual(num(r.lines[2].result), 723, "sum with token and literals")
        try expectEqual(num(r.lines[3].result), 518400, "token power")
        try expectEqual(r.tokens.count, 3, "three tokens rendered")
        try expect(r.tokens.allSatisfy { if case .active = $0.state { return true }; return false },
                   "all tokens stay active")
    },

    EngineCase("r47-token-multiple-markers") {
        let u0 = UUID(), u1 = UUID(), u2 = UUID()
        let content = "100\n200\nsum(" + r47M + ", " + r47M + ", 50)\nmin(" + r47M + ", " + r47M + ")"
        // Document (0-based) marker offsets: line 3 "sum(M, M, 50)" starts
        // at 8 (markers at 12 and 15); line 4 "min(M, M)" starts at 22
        // (markers at 26 and 29).
        let refs = [
            AnswerReference(sourceLineID: u0, labelLine: 1, location: 12),
            AnswerReference(sourceLineID: u1, labelLine: 2, location: 15),
            AnswerReference(sourceLineID: u0, labelLine: 1, location: 26),
            AnswerReference(sourceLineID: u0, labelLine: 1, location: 29),
        ]
        let r = resolveSheet(content: content, lineIDs: [u0, u1, u2, UUID()],
                             references: refs, rates: Rates(), decimalPlaces: 2)
        try expectEqual(num(r.lines[2].result), 350, "two distinct markers as args")
        try expectEqual(num(r.lines[3].result), 100, "min over the two markers")
    },

    EngineCase("r47-token-money-and-units-rejected") {
        // Money token into a function: hidden error — no 22.36, no $500.
        let u0 = UUID(), u1 = UUID()
        let c1 = "$500\nsqrt(" + r47M + ")"
        let r1 = resolveSheet(content: c1, lineIDs: [u0, u1],
                              references: [AnswerReference(sourceLineID: u0, labelLine: 1,
                                                           location: 5 + 5)],
                              rates: Rates(), decimalPlaces: 2)
        try expect(isErr(r1.lines[1].result), "money token into sqrt is a hidden error")

        // Unit-bearing token into a function: hidden error. (A bare
        // `10 km` source loses its unit in its own evaluation, so the
        // source must be a conversion line to carry a unit.)
        let w0 = UUID()
        let c2 = "10 km to m\nsqrt(" + r47M + ")"
        let r2 = resolveSheet(content: c2, lineIDs: [w0, UUID()],
                              references: [AnswerReference(sourceLineID: w0, labelLine: 1,
                                                           location: 16)],
                              rates: Rates(), decimalPlaces: 2)
        try expect(isErr(r2.lines[1].result), "unit token into sqrt is a hidden error")
    },

    EngineCase("r47-token-legacy-routes-unchanged") {
        let u0 = UUID()
        // Money-context token line: the legacy TokenExpr route,
        // byte-for-byte. The source must carry the currency itself.
        let c1 = "$720\n" + r47M + " + $60 tip"
        let r1 = resolveSheet(content: c1, lineIDs: [u0, UUID()],
                              references: [AnswerReference(sourceLineID: u0, labelLine: 1, location: 5)],
                              rates: Rates(), decimalPlaces: 2)
        try expectEqual(r1.lines[1].result, .number(value: 780, unit: "USD"), "legacy token money line")
        // Plain unitless token arithmetic (no call, no power): legacy route.
        let c2 = "720\n" + r47M + " × 2"
        let r2 = resolveSheet(content: c2, lineIDs: [u0, UUID()],
                              references: [AnswerReference(sourceLineID: u0, labelLine: 1, location: 4)],
                              rates: Rates(), decimalPlaces: 2)
        try expectEqual(num(r2.lines[1].result), 1440, "legacy plain token line")
        // Unitless token assignment without a function: legacy route.
        let c3 = "720\nx = " + r47M + " ÷ 2"
        let r3 = resolveSheet(content: c3, lineIDs: [u0, UUID()],
                              references: [AnswerReference(sourceLineID: u0, labelLine: 1, location: 8)],
                              rates: Rates(), decimalPlaces: 2)
        try expect(r3.lines[1].result == .variable(name: "x", value: 360), "legacy token assignment")
    },

    EngineCase("r47-token-assignment-with-functions") {
        let u0 = UUID()
        let content = "720\nx = sqrt(" + r47M + ")\nx × 2"
        let r = resolveSheet(content: content, lineIDs: [u0, UUID(), UUID()],
                             references: [AnswerReference(sourceLineID: u0, labelLine: 1, location: 13)],
                             rates: Rates(), decimalPlaces: 2)
        try expect(r.lines[1].result == .variable(name: "x", value: 26.83), "token function assignment")
        // The env keeps full precision (legacy behavior): 2 × sqrt(720).
        try expectEqual(num(r.lines[2].result), 53.67, "variable from the token assignment")
        // A failing token-function assignment must not create the variable.
        let w0 = UUID()
        let c2 = "720\ny = sqr(" + r47M + ")"
        let r2 = resolveSheet(content: c2, lineIDs: [w0, UUID()],
                              references: [AnswerReference(sourceLineID: w0, labelLine: 1, location: 12)],
                              rates: Rates(), decimalPlaces: 2)
        try expect(isErr(r2.lines[1].result), "failing token assignment errors")
    },

    // MARK: 5. Presentation

    EngineCase("r47-syntax-builtin-call-heads") {
        // A variable literally named `sum`: the call head stays base,
        // the non-call use stays a variable span.
        let s1 = SyntaxClassifier.spans(for: "sum = 5\nsum(1, 2) + sum",
                                        rates: Rates(), decimalPlaces: 2)
        let vars1 = s1[1].filter { $0.role == .variable }
        try expectEqual(vars1.count, 1, "one variable span (the bare sum)")
        try expectEqual(vars1.first?.range, NSRange(location: 12, length: 3),
                        "only the trailing bare name is highlighted")
        let s2 = SyntaxClassifier.spans(for: "min = 9\nmin + 1",
                                        rates: Rates(), decimalPlaces: 2)
        let vars2 = s2[1].filter { $0.role == .variable }
        try expectEqual(vars2.count, 1, "bare builtin-named variable highlighted")
        // No same-named variable: the call head is base text either way.
        let s3 = SyntaxClassifier.spans(for: "sqrt(9) + 1",
                                        rates: Rates(), decimalPlaces: 2)
        try expectEqual(s3[0].filter { $0.role == .variable }.count, 0, "no spans for a pure call")
    },

    EngineCase("r47-canonical-preserves-calls") {
        let a = NotebookFormatting.canonicalMathText("sum(1, 2) × 2")
        try expectEqual(a, "sum(1, 2) × 2", "separators and operators canonical")
        let b = NotebookFormatting.canonicalMathText("sqrt(9)+1")
        try expectEqual(b, "sqrt(9) + 1", "operator padding around a call")
        let c = NotebookFormatting.canonicalMathText(a)
        try expectEqual(c, a, "idempotent")
        // The caret map is exact: length = line length + 1, monotone.
        let (t, m) = NotebookFormatting.canonicalLine("sqrt(9)+1")!
        try expectEqual(t, "sqrt(9) + 1", "canonicalLine text")
        try expectEqual(m.count, ("sqrt(9)+1" as NSString).length + 1, "map length")
        try expect((0..<m.count - 1).allSatisfy { m[$0] <= m[$0 + 1] }, "map monotone")
    },

    EngineCase("r47-input-grouping-calls-safe") {
        let prefs = InputPreferences.defaults
        // A call with a 4+ digit argument gets grouped — the SAME
        // convention the evaluator uses, so the value is preserved.
        let r1 = InputFormatting.formatLine("sum(1234, 5678)", prefs: prefs)
        try expectEqual(r1?.text, "sum(1,234, 5,678)", "arguments grouped")
        // Re-formatting the grouped line is a no-op (idempotent).
        let r2 = InputFormatting.formatLine("sum(1,234, 5,678)", prefs: prefs)
        try expect(r2 == nil, "grouping idempotent")
        // The grouped line still evaluates to the original value.
        try expectEqual(try evalE("sum(1,234, 5,678)"), 6912, "grouped call value preserved")
        // Legacy free-line grouping unchanged.
        let r3 = InputFormatting.formatLine("1234", prefs: prefs)
        try expectEqual(r3?.text, "1,234", "legacy free grouping")
    },
]

private func evalMsg2(_ name: String, _ args: [Double]) -> String? {
    do { _ = try MathFunctions.evaluate(name, args: args); return nil }
    catch { return (error as? LocalizedError)?.errorDescription }
}
