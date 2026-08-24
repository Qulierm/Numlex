import Foundation
import NumlexCore

/// Portable failure type used by the assertion helpers below. Both the
/// Swift Testing suite and the standalone `swift run NumlexTests` runner
/// execute the same cases through this API.
public struct CaseFailure: Error, CustomStringConvertible {
    public let message: String
    public let location: String
    public init(message: String, location: String) {
        self.message = message
        self.location = location
    }
    public var description: String { "\(message) at \(location)" }
}

public func expect(_ condition: @autoclosure () -> Bool,
                   _ message: String = "expectation failed",
                   file: String = #fileID, line: Int = #line) throws {
    guard condition() else {
        throw CaseFailure(message: message, location: "\(file):\(line)")
    }
}

public func expectEqual<T: Equatable>(_ a: T, _ b: T,
                                      _ message: String = "",
                                      file: String = #fileID, line: Int = #line) throws {
    guard a == b else {
        throw CaseFailure(message: "\(message) — expected \(b), got \(a)",
                          location: "\(file):\(line)")
    }
}

public func expectClose(_ a: Double, _ b: Double, _ tolerance: Double = 0.0001,
                        _ message: String = "",
                        file: String = #fileID, line: Int = #line) throws {
    guard abs(a - b) <= tolerance else {
        throw CaseFailure(message: "\(message) — expected ~\(b), got \(a)",
                          location: "\(file):\(line)")
    }
}

public func expectThrows(_ message: String = "expected throw",
                         file: String = #fileID, line: Int = #line,
                         _ body: () throws -> Void) throws {
    do { try body() } catch { return }
    throw CaseFailure(message: message, location: "\(file):\(line)")
}

/// One named, independently executable engine test case.
public struct EngineCase: Sendable, CustomStringConvertible {
    public let name: String
    public let body: @Sendable () throws -> Void
    public init(_ name: String, body: @escaping @Sendable () throws -> Void) {
        self.name = name
        self.body = body
    }
    public var description: String { name }
}

public let engineCases: [EngineCase] = [
    // MARK: Expression grammar

    EngineCase("precedence") {
        try expectEqual(try evaluateExpression("2 + 3 * 4", variables: [:]), 14, "2 + 3 * 4")
    },
    EngineCase("parentheses") {
        try expectEqual(try evaluateExpression("(2 + 3) * 4", variables: [:]), 20, "(2+3)*4")
    },
    EngineCase("nested-parentheses") {
        try expectEqual(try evaluateExpression("2 * (3 + 4) * 5", variables: [:]), 70, "2*(3+4)*5")
    },
    EngineCase("left-assoc-subtraction") {
        try expectEqual(try evaluateExpression("10 - 4 - 2", variables: [:]), 4, "10-4-2")
    },
    EngineCase("power") {
        try expectEqual(try evaluateExpression("2 ^ 3", variables: [:]), 8, "2^3")
    },
    EngineCase("power-right-associative") {
        try expectEqual(try evaluateExpression("2 ^ 3 ^ 2", variables: [:]), 512, "2^3^2")
    },
    EngineCase("power-parentheses") {
        try expectEqual(try evaluateExpression("(2 ^ 3) ^ 2", variables: [:]), 64, "(2^3)^2")
    },
    EngineCase("percent-value") {
        try expectEqual(try evaluateExpression("50%", variables: [:]), 0.5, "50%")
    },
    EngineCase("percent-multiply") {
        try expectEqual(try evaluateExpression("200 * 10%", variables: [:]), 20, "200*10%")
    },
    EngineCase("percent-add") {
        try expectClose(try evaluateExpression("100 + 10%", variables: [:]), 100.1, 0.001, "100 + 10%")
    },
    EngineCase("unary-minus") {
        try expectEqual(try evaluateExpression("-5 + 3", variables: [:]), -2, "-5+3")
    },
    EngineCase("unary-minus-parentheses") {
        try expectEqual(try evaluateExpression("-(2 + 3)", variables: [:]), -5, "-(2+3)")
    },
    EngineCase("variable-reference") {
        try expectEqual(try evaluateExpression("x * 2", variables: ["x": 5]), 10, "x*2")
    },
    EngineCase("comma-grouping-stripped") {
        var vars: [String: Double] = [:]
        let rows = evaluateSheet("1,000 + 1", variables: &vars, rates: Rates(), decimalPlaces: 7)
        try expectEqual(rows.last?.result, LineResult.number(value: 1001, unit: nil), "1,000 + 1")
    },

    // MARK: Errors

    EngineCase("unknown-variable-throws") {
        try expectThrows("unknown variable") {
            _ = try evaluateExpression("y + 1", variables: [:])
        }
    },
    EngineCase("division-by-zero-throws") {
        try expectThrows("division by zero") {
            _ = try evaluateExpression("5 / 0", variables: [:])
        }
    },
    EngineCase("missing-parenthesis-throws") {
        try expectThrows("missing parenthesis") {
            _ = try evaluateExpression("((2 + 3)", variables: [:])
        }
    },
    EngineCase("incomplete-expression-throws") {
        try expectThrows("incomplete expression") {
            _ = try evaluateExpression("2 +", variables: [:])
        }
    },

    // MARK: Sheet semantics

    EngineCase("heading-line") {
        var vars: [String: Double] = [:]
        let rows = evaluateSheet("// Groceries\n12", variables: &vars, rates: Rates(), decimalPlaces: 7)
        try expectEqual(rows.first?.result, LineResult.title("Groceries"), "heading row")
        try expectEqual(rows.last?.result, LineResult.number(value: 12, unit: nil), "value row")
    },
    EngineCase("hash-comment-keeps-its-line") {
        // Strict contract: the # line occupies source line 0 as .blank;
        // the answer of "5" stays bound to source line 1.
        var vars: [String: Double] = [:]
        let rows = evaluateSheet("# hello\n5", variables: &vars, rates: Rates(), decimalPlaces: 7)
        try expectEqual(rows.count, 2, "one row per logical line")
        try expectEqual(rows[0].sourceLineIndex, 0)
        try expectEqual(rows[0].result, LineResult.blank, "# line is blank, but present")
        try expectEqual(rows[1].sourceLineIndex, 1)
        try expectEqual(rows[1].result, LineResult.number(value: 5, unit: nil))
    },
    EngineCase("leading-blanks-strict-indexing") {
        // The old collapsing behavior is gone: leading blanks each keep
        // their own indexed .blank row, so "5" sits on source line 2.
        var vars: [String: Double] = [:]
        let rows = evaluateSheet("\n\n5", variables: &vars, rates: Rates(), decimalPlaces: 7)
        try expectEqual(rows.count, 3, "one row per logical line")
        try expectEqual(rows.map { $0.result },
                        [LineResult.blank, .blank, .number(value: 5, unit: nil)])
        try expectEqual(rows[2].sourceLineIndex, 2, "value keeps its source index")
    },
    EngineCase("inner-blank-row") {
        var vars: [String: Double] = [:]
        let rows = evaluateSheet("5\n\n6", variables: &vars, rates: Rates(), decimalPlaces: 7)
        try expectEqual(rows.map { $0.result },
                        [.number(value: 5, unit: nil), .blank, .number(value: 6, unit: nil)], "inner blank")
        try expectEqual(rows.map { $0.sourceLineIndex }, [0, 1, 2], "indices stay line-aligned")
    },
    EngineCase("k-suffix") {
        var vars: [String: Double] = [:]
        let rows = evaluateSheet("5 k", variables: &vars, rates: Rates(), decimalPlaces: 7)
        try expectEqual(rows.last?.result, LineResult.number(value: 5000, unit: nil), "5 k")
    },
    EngineCase("m-suffix") {
        var vars: [String: Double] = [:]
        let rows = evaluateSheet("2 M", variables: &vars, rates: Rates(), decimalPlaces: 7)
        try expectEqual(rows.last?.result, LineResult.number(value: 2_000_000, unit: nil), "2 M")
    },
    EngineCase("assignment-row") {
        var vars: [String: Double] = [:]
        let rows = evaluateSheet("a = 5", variables: &vars, rates: Rates(), decimalPlaces: 7)
        try expectEqual(rows.map { $0.result }, [.variable(name: "a", value: 5)], "a = 5")
    },
    EngineCase("assignment-usage") {
        var vars: [String: Double] = [:]
        let rows = evaluateSheet("a = 5\na * 2", variables: &vars, rates: Rates(), decimalPlaces: 7)
        try expectEqual(rows.last?.result, LineResult.number(value: 10, unit: nil), "a * 2")
        try expectEqual(vars["a"], 5, "variable stored")
    },
    EngineCase("words-without-digits-skip") {
        var vars: [String: Double] = [:]
        let rows = evaluateSheet("hello world", variables: &vars, rates: Rates(), decimalPlaces: 7)
        try expectEqual(rows.map { $0.result }, [LineResult.skip], "plain words skip")
    },
    EngineCase("cyrillic-line-skip") {
        var vars: [String: Double] = [:]
        let rows = evaluateSheet("Самолет", variables: &vars, rates: Rates(), decimalPlaces: 7)
        try expectEqual(rows.map { $0.result }, [LineResult.skip], "cyrillic heading skips")
    },

    // MARK: Conversions

    EngineCase("linear-conversion-km") {
        var vars: [String: Double] = [:]
        let rows = evaluateSheet("10 km to meter", variables: &vars, rates: Rates(), decimalPlaces: 7)
        try expectEqual(rows.last?.result, LineResult.number(value: 10_000, unit: "meters"), "10 km to meter")
    },
    EngineCase("temperature-c-to-f") {
        var vars: [String: Double] = [:]
        let rows = evaluateSheet("100 C to F", variables: &vars, rates: Rates(), decimalPlaces: 7)
        try expectEqual(rows.last?.result, LineResult.number(value: 212, unit: "F°"), "100 C to F")
    },
    EngineCase("currency-rates-unavailable") {
        var vars: [String: Double] = [:]
        let rows = evaluateSheet("10 USD to RUB", variables: &vars, rates: Rates(), decimalPlaces: 7)
        try expectEqual(rows.last?.result, LineResult.error(message: "Rates unavailable"), "no rates")
    },
    EngineCase("currency-with-rates") {
        var vars: [String: Double] = [:]
        let rates = Rates(USD: 90, EUR: 100, EURUSD: 1.1)
        let rows = evaluateSheet("10 USD to RUB", variables: &vars, rates: rates, decimalPlaces: 7)
        try expectEqual(rows.last?.result, LineResult.number(value: 900, unit: "RUB"), "10 USD to RUB @ 90")
    },

    // MARK: Formatting

    EngineCase("format-integer-grouping") {
        try expectEqual(formatNumberForDisplay(1663), "1,663", "1663")
    },
    EngineCase("format-decimal") {
        try expectEqual(formatNumberForDisplay(0.5), "0.5", "0.5")
    },
    EngineCase("declared-variables") {
        let declared = declaredVariables("x = 1\ny = x")
        try expectEqual(declared["x"], true, "x declared")
        try expectEqual(declared["y"], true, "y declared")
    },
]
