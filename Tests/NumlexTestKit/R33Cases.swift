import Foundation
import NumlexCore

/// r33: global user constants — the persistent model, the pure
/// resolver, seeding of every evaluation path and the immutable
/// assignment protection.

private func rc(_ name: String, _ expression: String) -> UserConstant {
    UserConstant(name: name, expression: expression)
}

private func status(_ constants: [UserConstant], _ i: Int) -> ConstantResolver.RowStatus {
    ConstantResolver.resolve(constants).rows[i].status
}

private func qty(_ constants: [UserConstant], _ i: Int) -> TypedQty? {
    if case .valid(let q) = status(constants, i) { return q }
    return nil
}

private func resolveLines(_ content: String,
                          constants: [UserConstant],
                          rates: Rates = Rates(),
                          decimalPlaces: Int = 7) -> [SheetLine] {
    resolveSheet(content: content,
                 lineIDs: content.components(separatedBy: "\n").map { _ in UUID() },
                 references: [],
                 rates: rates,
                 decimalPlaces: decimalPlaces,
                 constants: constants).lines
}

public let r33Cases: [EngineCase] = [
    // MARK: Persistent model

    EngineCase("r33-settings-missing-key") {
        let json = """
        {"decimalPlaces":7,"fontSizeKey":"tf","language":"en","sheetName":"Sheet","lineNumbers":true,"fontColor":"white"}
        """
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        try expectEqual(s.customConstants, [UserConstant](), "missing key -> empty")
    },

    EngineCase("r33-settings-roundtrip") {
        var s = AppSettings.defaults
        let a = UserConstant(id: UUID(), name: "PI", expression: "3.141592653589793")
        let b = UserConstant(id: UUID(), name: "Monthly Rent", expression: "$2,500")
        s.customConstants = [a, b]
        let data = try JSONEncoder().encode(s)
        let s2 = try JSONDecoder().decode(AppSettings.self, from: data)
        try expectEqual(s2, s, "settings roundtrip equal")
        try expectEqual(s2.customConstants.map(\.id), [a.id, b.id], "stable UUIDs")
        try expectEqual(s2.customConstants.map(\.expression),
                        ["3.141592653589793", "$2,500"], "expressions verbatim")
    },

    EngineCase("r33-settings-defaults") {
        try expectEqual(AppSettings().customConstants, [UserConstant](), "default empty")
        let c = rc("PI", "1")
        let s = AppSettings(customConstants: [c])
        try expectEqual(s.customConstants.count, 1, "init argument")
        try expectEqual(s, AppSettings(customConstants: [c]), "Equatable")
    },

    // MARK: Resolver — valid values

    EngineCase("r33-resolver-basic-chain") {
        // Dependencies declared in REVERSE row order.
        let cs = [rc("Tau", "PI × 2"), rc("PI", "3.141592653589793"),
                  rc("Sales Tax", "20%")]
        let r = ConstantResolver.resolve(cs)
        try expectEqual(r.rows[0].status, .valid(.scalar(6.283185307179586)), "Tau")
        try expectEqual(r.rows[1].status, .valid(.scalar(3.141592653589793)),
                        "PI full precision")
        try expectEqual(r.rows[2].status, .valid(.scalar(0.2)), "20% percent")
    },

    EngineCase("r33-resolver-money-chain") {
        let cs = [rc("Annual Rent", "Monthly Rent × 12"),
                  rc("Monthly Rent", "$2,500")]
        let r = ConstantResolver.resolve(cs)
        try expectEqual(r.rows[1].status, .valid(.money(2500, code: "USD")), "rent")
        try expectEqual(r.rows[0].status, .valid(.money(30000, code: "USD")),
                        "annual keeps the single code")
    },

    EngineCase("r33-resolver-valid-shapes") {
        try expectEqual(status([rc("shape1", "(2 + 3) × 4")], 0),
                        .valid(.scalar(20)), "parentheses")
        try expectEqual(status([rc("shape2", "CA$100")], 0),
                        .valid(.money(100, code: "CAD")), "letter dollar marker")
        try expectEqual(status([rc("shape3", "100 IDR")], 0),
                        .valid(.money(100, code: "IDR")), "ISO annotation")
        try expectEqual(status([rc("shape4", "€50 + 5")], 0),
                        .valid(.money(55, code: "EUR")), "money arithmetic")
    },

    // MARK: Resolver — limits and name grammar

    EngineCase("r33-resolver-limits") {
        let many = (1...100).map { rc("c\($0)", "1") }
        let r = ConstantResolver.resolve(many)
        try expectEqual(r.rows.filter {
            if case .valid = $0.status { return true } else { return false }
        }.count, 100, "100 rows all valid")
        let over = many + [rc("c101", "1")]
        try expectEqual(ConstantResolver.resolve(over).rows[100].status,
                        .exceedsLimit, "101st row exceeds the limit")
        try expectEqual(status([rc(String(repeating: "a", count: 41), "1")], 0),
                        .invalidName, "41-char name")
        try expectEqual(status([rc("Long Expr", String(repeating: "9", count: 257))], 0),
                        .invalidExpression, "257-char expression")
    },

    EngineCase("r33-resolver-name-grammar") {
        try expectEqual(status([rc("", "")], 0), .empty, "empty row")
        try expectEqual(status([rc("X", "")], 0), .incomplete, "missing expression")
        try expectEqual(status([rc("", "1")], 0), .incomplete, "missing name")
        try expectEqual(status([rc("1abc", "1")], 0), .invalidName, "digit-first")
        try expectEqual(status([rc("a b c d e f g", "1")], 0), .invalidName,
                        "seven words")
        try expectEqual(status([rc("Sales Tax", "20%")], 0),
                        .valid(.scalar(0.2)), "multiword OK")
    },

    // MARK: Resolver — duplicates and reserved

    EngineCase("r33-resolver-duplicates") {
        let cs = [rc("PI", "1"), rc("pi  ", "2"), rc("Pi", "3")]
        let r = ConstantResolver.resolve(cs)
        for i in 0..<3 {
            try expectEqual(r.rows[i].status, .duplicate, "row \(i) duplicate")
        }
        // A duplicate name is INACTIVE: a reference to it is unknown.
        let cs2 = [rc("PI", "1"), rc("pi", "2"), rc("Use", "PI + 1")]
        let r2 = ConstantResolver.resolve(cs2)
        try expectEqual(r2.rows[2].status, .invalidDependency, "dup name inactive")
    },

    EngineCase("r33-resolver-reserved") {
        for name in ["g", "m", "USD", "today", "may", "year", "dollar",
                     "km", "to", "in", "per", "as", "of"] {
            try expectEqual(status([rc(name, "1")], 0), .reserved,
                            "reserved: \(name)")
        }
        // Ordinary names stay usable.
        try expectEqual(status([rc("PI", "1")], 0), .valid(.scalar(1)), "PI usable")
        try expectEqual(status([rc("Sales Tax", "20%")], 0),
                        .valid(.scalar(0.2)), "Sales Tax usable")
    },

    // MARK: Resolver — dependencies, cycles, rejections

    EngineCase("r33-resolver-unknown") {
        try expectEqual(status([rc("X", "foo + 1")], 0), .invalidDependency,
                        "unknown identifier")
    },

    EngineCase("r33-resolver-cycle") {
        let r = ConstantResolver.resolve([rc("one", "two + 1"), rc("two", "one")])
        try expectEqual(r.rows[0].status, .cycle, "A cycle")
        try expectEqual(r.rows[1].status, .cycle, "B cycle")
        try expectEqual(status([rc("one", "one + 1")], 0), .cycle, "self-reference")
        // A dependency on a failed row is a dependency error, not a cycle.
        let r2 = ConstantResolver.resolve([rc("dep1", "dep2 + 1"), rc("dep2", "10^400")])
        try expectEqual(r2.rows[1].status, .invalidExpression, "dep2 overflow")
        try expectEqual(r2.rows[0].status, .invalidDependency, "dep1 inactive dep")
    },

    EngineCase("r33-resolver-rejections") {
        try expectEqual(status([rc("rejA", "x = 5")], 0), .invalidExpression,
                        "assignment rejected")
        try expectEqual(status([rc("rejB", "10 km to meter")], 0),
                        .invalidDependency, "conversion rejected")
        try expectEqual(status([rc("rejC", "today + 1")], 0), .invalidDependency,
                        "date rejected")
        // NO unit stripping: 9.81 m/s² is invalid, never 9.81.
        let s = status([rc("rejD", "9.81 m/s²")], 0)
        try expect(s != .valid(.scalar(9.81)), "unit value never stripped")
        try expect(s == .invalidDependency || s == .invalidExpression,
                   "unit value invalid: \(s)")
        try expectEqual(status([rc("rejE", "\u{FFFC} + 1")], 0),
                        .invalidExpression, "token marker rejected")
    },

    EngineCase("r33-resolver-mixed-money") {
        try expectEqual(status([rc("mixA", "$5 + €5")], 0), .invalidExpression,
                        "two currencies")
        let r = ConstantResolver.resolve([rc("mixB", "$5"), rc("mixC", "mixB + €5")])
        try expectEqual(r.rows[1].status, .invalidExpression, "mixed via dep")
    },

    EngineCase("r33-resolver-inactive") {
        // A failing row reserves no name: the word is assignable in a
        // sheet and unknown as a constant reference.
        let r = ConstantResolver.resolve([rc("failA", "10^400"), rc("failB", "failA + 1")])
        try expectEqual(r.rows[0].status, .invalidExpression, "A overflow")
        try expectEqual(r.rows[1].status, .invalidDependency, "B unknown (A inactive)")
        // Deterministic across calls.
        let cs = [rc("dupB", "dupA + 1"), rc("dupA", "2"), rc("dupA", "9"), rc("z", "10^999")]
        try expectEqual(ConstantResolver.resolve(cs), ConstantResolver.resolve(cs),
                        "deterministic")
    },

    // MARK: Sheets — seeding every path

    EngineCase("r33-sheet-first-line") {
        let cs = [rc("PI", "3.141592653589793")]
        let lines = resolveLines("PI × 2", constants: cs)
        guard case .number(let v, let u) = lines[0].result else {
            throw CaseFailure(message: "PI × 2 must be a number, got \(lines[0].result)",
                              location: "R33Cases")
        }
        try expectClose(v, 6.2831853072, 1e-9, "PI × 2 value (line pipeline 10dp)")
        try expectEqual(u, Optional<String>.none, "unitless")
    },

    EngineCase("r33-sheet-casefold-multispace") {
        let cs = [rc("PI", "3.141592653589793"), rc("Sales Tax", "20%")]
        let a = resolveLines("pi   × 2", constants: cs)
        guard case .number(let v, _) = a[0].result else {
            throw CaseFailure(message: "pi × 2 must evaluate, got \(a[0].result)",
                              location: "R33Cases")
        }
        try expectClose(v, 6.2831853072, 1e-9, "casefold PI")
        let b = resolveLines("SALES   TAX × 100", constants: cs)
        guard case .number(let w, _) = b[0].result else {
            throw CaseFailure(message: "SALES TAX × 100 must evaluate, got \(b[0].result)",
                              location: "R33Cases")
        }
        try expectClose(w, 20, 1e-12, "multiwhitespace name")
    },

    EngineCase("r33-sheet-money-formula") {
        let cs = [rc("Monthly Rent", "$2,500")]
        let a = resolveLines("Monthly Rent × 12", constants: cs)
        guard case .money(let v, let c) = a[0].result else {
            throw CaseFailure(message: "rent × 12 must be money, got \(a[0].result)",
                              location: "R33Cases")
        }
        try expectClose(v, 30000, 1e-9, "annual rent")
        try expectEqual(c, "USD", "code carried")
        // Fiat conversion of a money constant with synthetic rates.
        let rates = Rates(base: "USD", rates: ["USD": 1, "EUR": 1.1])
        let b = resolveLines("Monthly Rent in EUR", constants: cs, rates: rates)
        guard case .number(let w, let u) = b[0].result else {
            throw CaseFailure(message: "rent in EUR must convert, got \(b[0].result)",
                              location: "R33Cases")
        }
        try expectClose(w, 2750, 1e-9, "2500 × 1.1")
        try expectEqual(u ?? "<none>", "EUR", "target unit")
    },

    EngineCase("r33-sheet-assignment-protected") {
        let cs = [rc("PI", "3.141592653589793"), rc("Sales Tax", "20%"),
                  rc("Monthly Rent", "$2,500")]
        let lines = resolveLines(
            "PI = 3\nSales Tax = 30%\nMonthly Rent = $1\nx = 4\nx × 2",
            constants: cs)
        for i in 0..<3 {
            guard case .error(let msg) = lines[i].result else {
                throw CaseFailure(message: "row \(i) must be an error, got \(lines[i].result)",
                                  location: "R33Cases")
            }
            try expectEqual(msg, "Cannot assign to constant", "row \(i) message")
        }
        guard case .variable(let n, let v) = lines[3].result else {
            throw CaseFailure(message: "x = 4 must assign, got \(lines[3].result)",
                              location: "R33Cases")
        }
        try expectEqual(n, "x", "ordinary assignment works")
        try expectClose(v, 4, 0, "x value")
        guard case .number(let w, _) = lines[4].result else {
            throw CaseFailure(message: "x × 2 must evaluate, got \(lines[4].result)",
                              location: "R33Cases")
        }
        try expectClose(w, 8, 0, "x × 2")
    },

    EngineCase("r33-sheet-inactive-reserves-nothing") {
        // A RESERVED constant row is inactive: the word is a plain
        // local variable again.
        let cs = [UserConstant(name: "g", expression: "9.81")]
        let lines = resolveLines("g = 5", constants: cs)
        guard case .variable(let n, let v) = lines[0].result else {
            throw CaseFailure(message: "g = 5 must assign, got \(lines[0].result)",
                              location: "R33Cases")
        }
        try expectEqual(n, "g", "reserved row reserves nothing")
        try expectClose(v, 5, 0, "g value")
    },

    EngineCase("r33-sheet-token") {
        let cs = [rc("PI", "3.141592653589793")]
        let u0 = UUID(), u1 = UUID()
        let line1 = "PI × 2"
        let line2 = "\u{FFFC} × 2"
        let content = line1 + "\n" + line2
        let refs = [AnswerReference(sourceLineID: u0, labelLine: 1,
                                    location: (line1 as NSString).length + 1)]
        let (lines, tokens) = resolveSheet(content: content, lineIDs: [u0, u1],
                                           references: refs, rates: Rates(),
                                           decimalPlaces: 7, constants: cs)
        guard case .number(let v, _) = lines[0].result else {
            throw CaseFailure(message: "line 0 must be a number, got \(lines[0].result)",
                              location: "R33Cases")
        }
        try expectClose(v, 6.2831853072, 1e-9, "source value")
        guard case .number(let w, _) = lines[1].result else {
            throw CaseFailure(message: "token line must be a number, got \(lines[1].result)",
                              location: "R33Cases")
        }
        try expectClose(w, 12.5663706, 1e-9, "token × 2 (7dp line)")
        guard case .active(let tv, _, _)? = tokens.last?.state else {
            throw CaseFailure(message: "token must be active, got \(String(describing: tokens.last?.state))",
                              location: "R33Cases")
        }
        try expectClose(tv, 6.2831853072, 1e-9, "token display value")
        // Token-expression assignment to a constant is blocked too.
        let u2 = UUID(), u3 = UUID()
        let c2 = "5\nPI = \u{FFFC}"
        let refs2 = [AnswerReference(sourceLineID: u2, labelLine: 1,
                                     location: 6)]
        let (lines2, _) = resolveSheet(content: c2, lineIDs: [u2, u3],
                                       references: refs2, rates: Rates(),
                                       decimalPlaces: 7, constants: cs)
        guard case .error(let msg) = lines2[1].result else {
            throw CaseFailure(message: "token assignment must error, got \(lines2[1].result)",
                              location: "R33Cases")
        }
        try expectEqual(msg, "Cannot assign to constant", "token assignment blocked")
    },

    EngineCase("r33-syntax-constants") {
        let cs = [rc("Sales Tax", "20%")]
        let spans = SyntaxClassifier.spans(
            for: "100 × Sales Tax", rates: Rates(), decimalPlaces: 7,
            constants: cs)
        let nameSpan = NSRange(location: 6, length: 9)
        try expect(spans[0].contains {
            $0.role == .variable && $0.range == nameSpan
        }, "Sales Tax paints green")
        let plain = SyntaxClassifier.spans(
            for: "PI", rates: Rates(), decimalPlaces: 7,
            constants: [rc("PI", "1")])
        try expect(plain[0].contains {
            $0.role == .variable && $0.range == NSRange(location: 0, length: 2)
        }, "bare PI paints green")
    },

    EngineCase("r33-prev-answer") {
        let cs = [rc("Sales Tax", "20%")]
        let content = "100 × Sales Tax\n"
        let plan = PreviousAnswerPlan.plan(
            content: content, lineIDs: [UUID(), UUID()],
            caret: (content as NSString).length, op: "+",
            rates: Rates(), decimalPlaces: 7, references: [], constants: cs)
        try expect(plan != nil, "constant-driven line is answerable")
        try expectEqual(plan?.sourceLineIndex, Optional<Int>(0), "source line")
    },

    EngineCase("r33-autotitle") {
        let cs = [rc("Sales Tax", "20%")]
        try expectEqual(
            Sheet.autoTitle(from: "100 × Sales Tax", fallback: "Sheet",
                            constants: cs),
            "100 × Sales Tax", "constant first calculation titles the sheet")
        try expectEqual(
            Sheet.autoTitle(from: "100 × Sales Tax", fallback: "Sheet"),
            "Sheet", "without constants it stays prose")
    },

    EngineCase("r33-live-change") {
        let content = "PI × 2"
        let ids = [UUID(), UUID()]
        let a = resolveSheet(content: content, lineIDs: ids, references: [],
                             rates: Rates(), decimalPlaces: 7,
                             constants: [rc("PI", "3.141592653589793")]).lines
        let b = resolveSheet(content: content, lineIDs: ids, references: [],
                             rates: Rates(), decimalPlaces: 7,
                             constants: [rc("PI", "2")]).lines
        guard case .number(let va, _) = a[0].result,
              case .number(let vb, _) = b[0].result else {
            throw CaseFailure(message: "both must evaluate", location: "R33Cases")
        }
        try expectClose(va, 6.2831853072, 1e-9, "before")
        try expectClose(vb, 4, 1e-12, "after — same content, new value")
    },

    EngineCase("r33-legacy-evalline") {
        var v: [String: Double] = [:]
        let r = evalLine("pi × 2", variables: &v, rates: Rates(), decimalPlaces: 7,
                         constants: [rc("PI", "3.141592653589793")])
        guard case .number(let val, let u)? = r else {
            throw CaseFailure(message: "evalLine must evaluate, got \(String(describing: r))",
                              location: "R33Cases")
        }
        try expectClose(val, 6.2831853072, 1e-9, "evalLine constant")
        try expectEqual(u, Optional<String>.none, "unitless")
        let m = evalLine("Monthly Rent", variables: &v, rates: Rates(),
                         decimalPlaces: 7,
                         constants: [rc("Monthly Rent", "$2,500")])
        guard case .money(let mv, let mc)? = m else {
            throw CaseFailure(message: "money constant must be money, got \(String(describing: m))",
                              location: "R33Cases")
        }
        try expectClose(mv, 2500, 1e-9, "money value")
        try expectEqual(mc, "USD", "money code")
    },
]
