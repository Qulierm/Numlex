import Foundation
import NumlexCore

/// Focused cases for the range-aware syntax classifier. Ranges are UTF-16
/// offsets inside the single line under test.
public let syntaxCases: [EngineCase] = [
    EngineCase("syntax-arithmetic-plain") {
        let spans = SyntaxClassifier.spans(for: "12 + 30 * 2", rates: Rates(), decimalPlaces: 7)
        let numbers = spans[0].filter { $0.role == .number }.map { $0.range }
        try expectEqual(numbers,
                        [NSRange(location: 0, length: 2),
                         NSRange(location: 5, length: 2),
                         NSRange(location: 10, length: 1)],
                        "number spans")
        try expectEqual(spans[0].filter { $0.role != .number }.count, 0,
                        "operators stay base")
    },

    EngineCase("syntax-variable-assignment-use") {
        let spans = SyntaxClassifier.spans(for: "x = 5\nx * 3", rates: Rates(), decimalPlaces: 7)
        let line1 = spans[0]
        try expectEqual(line1.filter { $0.role == .variable }.map { $0.range },
                        [NSRange(location: 0, length: 1)], "declared name")
        try expectEqual(line1.filter { $0.role == .number }.map { $0.range },
                        [NSRange(location: 4, length: 1)], "assigned literal")
        let line2 = spans[1]
        try expectEqual(line2.filter { $0.role == .variable }.map { $0.range },
                        [NSRange(location: 0, length: 1)], "used variable")
        try expectEqual(line2.filter { $0.role == .number }.map { $0.range },
                        [NSRange(location: 4, length: 1)], "literal")
    },

    EngineCase("syntax-conversion-measurement") {
        let spans = SyntaxClassifier.spans(for: "10 km to meter", rates: Rates(), decimalPlaces: 7)
        try expectEqual(spans[0].filter { $0.role == .number }.map { $0.range },
                        [NSRange(location: 0, length: 2)], "leading value stays number")
        try expectEqual(spans[0].filter { $0.role == .conversion }.map { $0.range },
                        [NSRange(location: 3, length: 2),
                         NSRange(location: 9, length: 5)], "km / meter; `to` stays base")
    },

    EngineCase("syntax-conversion-temperature") {
        let spans = SyntaxClassifier.spans(for: "100 C to F", rates: Rates(), decimalPlaces: 7)
        try expectEqual(spans[0].filter { $0.role == .number }.map { $0.range },
                        [NSRange(location: 0, length: 3)])
        try expectEqual(spans[0].filter { $0.role == .conversion }.map { $0.range },
                        [NSRange(location: 4, length: 1),
                         NSRange(location: 9, length: 1)], "C / F; `to` stays base")
    },

    EngineCase("syntax-conversion-currency") {
        let rates = Rates(USD: 90, EUR: 100, EURUSD: 1.1)
        let spans = SyntaxClassifier.spans(for: "10 USD to RUB", rates: rates, decimalPlaces: 7)
        try expectEqual(spans[0].filter { $0.role == .number }.map { $0.range },
                        [NSRange(location: 0, length: 2)])
        try expectEqual(spans[0].filter { $0.role == .conversion }.map { $0.range },
                        [NSRange(location: 3, length: 3),
                         NSRange(location: 10, length: 3)], "USD / RUB; `to` stays base")
    },

    EngineCase("syntax-prose-stays-base") {
        let spans = SyntaxClassifier.spans(for: "shopping list\nhello world",
                                           rates: Rates(), decimalPlaces: 7)
        try expectEqual(spans.count, 2)
        try expectEqual(spans[0].count, 0, "prose is .skip: no spans")
        try expectEqual(spans[1].count, 0)
    },

    EngineCase("syntax-title-and-comment") {
        let spans = SyntaxClassifier.spans(for: "// My sheet\n# note",
                                           rates: Rates(), decimalPlaces: 7)
        try expectEqual(spans[0].count, 0, "title owns its styling")
        try expectEqual(spans[1].count, 0)
    },

    EngineCase("syntax-invalid-expression") {
        let spans = SyntaxClassifier.spans(for: "12 + \nx = ", rates: Rates(), decimalPlaces: 7)
        try expectEqual(spans[0].filter { $0.role == .number }.map { $0.range },
                        [NSRange(location: 0, length: 2)], "incomplete expression keeps its literal")
        try expectEqual(spans[0].count, 1, "only the literal is spanned")
        try expectEqual(spans[1].count, 0, "`x = ` has no literal and x is unknown")
    },

    EngineCase("syntax-error-division-by-zero") {
        let spans = SyntaxClassifier.spans(for: "12 / 0", rates: Rates(), decimalPlaces: 7)
        try expectEqual(spans[0].filter { $0.role == .number }.map { $0.range },
                        [NSRange(location: 0, length: 2),
                         NSRange(location: 5, length: 1)], "both literals stay numbers")
        try expectEqual(spans[0].count, 2)
    },

    EngineCase("syntax-error-unavailable-currency") {
        // No rates at all: the line is an evaluation error, yet the
        // conversion grammar still paints value + unit words, and `to`
        // stays base.
        let spans = SyntaxClassifier.spans(for: "10 USD to RUB", rates: Rates(), decimalPlaces: 7)
        try expectEqual(spans[0].filter { $0.role == .number }.map { $0.range },
                        [NSRange(location: 0, length: 2)], "leading value stays number")
        try expectEqual(spans[0].filter { $0.role == .conversion }.map { $0.range },
                        [NSRange(location: 3, length: 3),
                         NSRange(location: 10, length: 3)], "unit words; `to` stays base")
        try expectEqual(spans[0].count, 3)
    },

    EngineCase("syntax-error-known-variable") {
        let spans = SyntaxClassifier.spans(for: "x = 5\nx + (5", rates: Rates(), decimalPlaces: 7)
        try expectEqual(spans[1].filter { $0.role == .variable }.map { $0.range },
                        [NSRange(location: 0, length: 1)], "partial expression keeps known variable")
        try expectEqual(spans[1].filter { $0.role == .number }.map { $0.range },
                        [NSRange(location: 5, length: 1)], "partial expression keeps its literal")
        try expectEqual(spans[1].count, 2)
    },

    EngineCase("syntax-decimals-unary-thousands") {
        let spans = SyntaxClassifier.spans(
            for: "-1.5 + 2\n1,234 + 5\nx = 1\n0.25 * x",
            rates: Rates(), decimalPlaces: 7)
        try expectEqual(spans[0].filter { $0.role == .number }.map { $0.range },
                        [NSRange(location: 1, length: 3),
                         NSRange(location: 7, length: 1)], "unary sign stays operator")
        try expectEqual(spans[1].filter { $0.role == .number }.map { $0.range },
                        [NSRange(location: 0, length: 5),
                         NSRange(location: 8, length: 1)], "thousands separator")
        try expectEqual(spans[2].count, 2, "assignment spans")
        try expectEqual(spans[3].filter { $0.role == .number }.map { $0.range },
                        [NSRange(location: 0, length: 4)])
        try expectEqual(spans[3].filter { $0.role == .variable }.map { $0.range },
                        [NSRange(location: 7, length: 1)], "known variable in expression")
    },

    EngineCase("syntax-multiple-lines-utf16") {
        // Non-ASCII text shifts UTF-16 offsets; spans must stay line-local
        // and consistent with the evaluator's view of the same text.
        let source = "значение x\nx = 5\nx * 2"
        let spans = SyntaxClassifier.spans(for: source, rates: Rates(), decimalPlaces: 7)
        try expectEqual(spans.count, 3)
        try expectEqual(spans[0].count, 0, "prose line untouched")
        let line2 = spans[1]
        try expectEqual(line2.filter { $0.role == .variable }.map { $0.range },
                        [NSRange(location: 0, length: 1)])
        try expectEqual(spans[2].filter { $0.role == .number }.map { $0.range },
                        [NSRange(location: 4, length: 1)])
    },

    EngineCase("syntax-empty-document") {
        let spans = SyntaxClassifier.spans(for: "", rates: Rates(), decimalPlaces: 7)
        try expectEqual(spans.count, 1)
        try expectEqual(spans[0].count, 0)
    }
]
