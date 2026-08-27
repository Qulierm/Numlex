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
        // r21: operator glyphs get their own role (base-colored by
        // default, so the default look is unchanged).
        try expectEqual(spans[0].filter { $0.role == .operatorGlyph }.map { $0.range },
                        [NSRange(location: 3, length: 1),
                         NSRange(location: 8, length: 1)],
                        "`+` and `*` are operator glyphs")
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
        let rates = Rates(base: "USD", rates: ["USD": 1, "EUR": 1.1, "RUB": 90])
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
        // `#` lines carry explicit heading spans (marker + body).
        try expectEqual(spans[1].filter { $0.role == .hashMarker }.map { $0.range },
                        [NSRange(location: 0, length: 1)])
        try expectEqual(spans[1].filter { $0.role == .hashBody }.map { $0.range },
                        [NSRange(location: 1, length: 5)], "space + note is the body")
    },

    EngineCase("syntax-hash-heading") {
        // `#` lines are non-evaluated (no answers, no variable flow),
        // but the classifier gives them explicit marker/body spans with
        // UTF-16 line-local ranges.
        let spans = SyntaxClassifier.spans(for: "# Heading", rates: Rates(), decimalPlaces: 7)
        try expectEqual(spans[0].filter { $0.role == .hashMarker }.map { $0.range },
                        [NSRange(location: 0, length: 1)], "single-char marker")
        try expectEqual(spans[0].filter { $0.role == .hashBody }.map { $0.range },
                        [NSRange(location: 1, length: 8)], "body = everything after #")
        try expectEqual(spans[0].count, 2, "no token spans inside a heading")

        // Lone `#`: marker only, no body span.
        let lone = SyntaxClassifier.spans(for: "#", rates: Rates(), decimalPlaces: 7)
        try expectEqual(lone[0].count, 1)
        try expectEqual(lone[0][0].role, .hashMarker)
        try expectEqual(lone[0][0].range, NSRange(location: 0, length: 1))

        // `#text` (no space): body starts immediately after the marker.
        let tight = SyntaxClassifier.spans(for: "#text", rates: Rates(), decimalPlaces: 7)
        try expectEqual(tight[0].filter { $0.role == .hashBody }.map { $0.range },
                        [NSRange(location: 1, length: 4)])

        // Multiple heading lines followed by math: the heading spans are
        // line-local and the later expression classifies normally.
        let multi = SyntaxClassifier.spans(
            for: "# H\n#\n#text\n5 + 3", rates: Rates(), decimalPlaces: 7
        )
        try expectEqual(multi.count, 4)
        try expectEqual(multi[0].filter { $0.role == .hashBody }.map { $0.range },
                        [NSRange(location: 1, length: 2)])
        try expectEqual(multi[1].count, 1, "lone # is marker only")
        try expectEqual(multi[2].filter { $0.role == .hashBody }.map { $0.range },
                        [NSRange(location: 1, length: 4)])
        try expectEqual(multi[3].filter { $0.role == .number }.map { $0.range },
                        [NSRange(location: 0, length: 1),
                         NSRange(location: 4, length: 1)],
                        "arithmetic after headings is unaffected")
    },

    EngineCase("syntax-partial-assignment-lhs") {
        // A syntactically valid identifier before `=` is a variable
        // immediately — no valid RHS required. Visual only: the
        // evaluator still returns .error and sets nothing.
        let spans = SyntaxClassifier.spans(for: "hello =", rates: Rates(), decimalPlaces: 7)
        try expectEqual(spans[0].filter { $0.role == .variable }.map { $0.range },
                        [NSRange(location: 0, length: 5)], "LHS green with no RHS")
        try expectEqual(spans[0].filter { $0.role == .operatorGlyph }.map { $0.range },
                        [NSRange(location: 6, length: 1)], "`=` is an operator glyph")
        try expectEqual(spans[0].count, 2, "LHS variable + `=`")

        let trailing = SyntaxClassifier.spans(for: "hello = ", rates: Rates(), decimalPlaces: 7)
        try expectEqual(trailing[0].filter { $0.role == .variable }.map { $0.range },
                        [NSRange(location: 0, length: 5)], "trailing space still LHS")

        // Leading whitespace is allowed, matching the evaluator's
        // trimmed LHS; the span stays on the identifier itself.
        let indented = SyntaxClassifier.spans(for: "  hello = 1",
                                              rates: Rates(), decimalPlaces: 7)
        try expectEqual(indented[0].filter { $0.role == .variable }.map { $0.range },
                        [NSRange(location: 2, length: 5)], "span on the identifier")
    },

    EngineCase("syntax-partial-assignment-rules") {
        let spans = SyntaxClassifier.spans(
            for: "x = 5\nx =\n2hello = 1\nhello",
            rates: Rates(), decimalPlaces: 7
        )
        // Valid line unchanged: LHS variable + RHS number.
        try expectEqual(spans[0].filter { $0.role == .variable }.map { $0.range },
                        [NSRange(location: 0, length: 1)])
        // Known variable with empty RHS: exactly ONE LHS span
        // (no duplicate from the known-variable pass).
        try expectEqual(spans[1].filter { $0.role == .variable }.map { $0.range },
                        [NSRange(location: 0, length: 1)])
        try expectEqual(spans[1].filter { $0.role == .variable }.count, 1,
                        "no duplicate LHS span")
        try expectEqual(spans[1].filter { $0.role == .operatorGlyph }.count, 1,
                        "`=` operator glyph")
        // Invalid LHS: never a variable; the leading `2` and the RHS
        // literal keep their number spans.
        try expectEqual(spans[2].filter { $0.role == .variable }.count, 0)
        try expectEqual(spans[2].filter { $0.role == .number }.map { $0.range },
                        [NSRange(location: 0, length: 1),
                         NSRange(location: 9, length: 1)])
        // Bare identifier without `=` stays prose: no spans.
        try expectEqual(spans[3].count, 0)

        // UTF-16 regression: non-ASCII before the `=` is not a valid
        // ASCII identifier, and offsets stay UTF-16-consistent.
        let utf16 = SyntaxClassifier.spans(for: "привет = 5",
                                           rates: Rates(), decimalPlaces: 7)
        try expectEqual(utf16[0].filter { $0.role == .variable }.count, 0,
                        "Cyrillic LHS is not a variable")
        try expectEqual(utf16[0].filter { $0.role == .number }.map { $0.range },
                        [NSRange(location: 9, length: 1)], "UTF-16 offsets")
    },

    EngineCase("syntax-invalid-expression") {
        let spans = SyntaxClassifier.spans(for: "12 + \nx = ", rates: Rates(), decimalPlaces: 7)
        try expectEqual(spans[0].filter { $0.role == .number }.map { $0.range },
                        [NSRange(location: 0, length: 2)], "incomplete expression keeps its literal")
        try expectEqual(spans[0].filter { $0.role == .operatorGlyph }.map { $0.range },
                        [NSRange(location: 3, length: 1)], "`+` operator glyph")
        try expectEqual(spans[0].count, 2, "literal + operator")
        // `x = ` is a partial assignment: the valid LHS is a variable
        // immediately (no duplicate, no literal present).
        try expectEqual(spans[1].filter { $0.role == .variable }.map { $0.range },
                        [NSRange(location: 0, length: 1)])
        try expectEqual(spans[1].count, 2, "variable + `=` operator")
    },

    EngineCase("syntax-error-division-by-zero") {
        let spans = SyntaxClassifier.spans(for: "12 / 0", rates: Rates(), decimalPlaces: 7)
        try expectEqual(spans[0].filter { $0.role == .number }.map { $0.range },
                        [NSRange(location: 0, length: 2),
                         NSRange(location: 5, length: 1)], "both literals stay numbers")
        try expectEqual(spans[0].filter { $0.role == .operatorGlyph }.map { $0.range },
                        [NSRange(location: 3, length: 1)], "`/` operator glyph")
        try expectEqual(spans[0].count, 3)
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
                         NSRange(location: 10, length: 3)], "unit words")
        // `to` keeps its own specifier role in the conversion context.
        try expectEqual(spans[0].filter { $0.role == .specifier }.map { $0.range },
                        [NSRange(location: 7, length: 2)], "`to` specifier")
        try expectEqual(spans[0].count, 4)
    },

    EngineCase("syntax-error-known-variable") {
        let spans = SyntaxClassifier.spans(for: "x = 5\nx + (5", rates: Rates(), decimalPlaces: 7)
        try expectEqual(spans[1].filter { $0.role == .variable }.map { $0.range },
                        [NSRange(location: 0, length: 1)], "partial expression keeps known variable")
        try expectEqual(spans[1].filter { $0.role == .number }.map { $0.range },
                        [NSRange(location: 5, length: 1)], "partial expression keeps its literal")
        try expectEqual(spans[1].filter { $0.role == .operatorGlyph }.map { $0.range },
                        [NSRange(location: 2, length: 1)], "`+` operator glyph")
        try expectEqual(spans[1].count, 3)
    },

    EngineCase("syntax-decimals-unary-thousands") {
        let spans = SyntaxClassifier.spans(
            for: "-1.5 + 2\n1,234 + 5\nx = 1\n0.25 * x",
            rates: Rates(), decimalPlaces: 7)
        try expectEqual(spans[0].filter { $0.role == .number }.map { $0.range },
                        [NSRange(location: 1, length: 3),
                         NSRange(location: 7, length: 1)], "unary sign excluded from numbers")
        try expectEqual(spans[0].filter { $0.role == .operatorGlyph }.map { $0.range },
                        [NSRange(location: 0, length: 1),
                         NSRange(location: 5, length: 1)], "unary sign and `+` are operator glyphs")
        try expectEqual(spans[1].filter { $0.role == .number }.map { $0.range },
                        [NSRange(location: 0, length: 5),
                         NSRange(location: 8, length: 1)], "thousands separator")
        try expectEqual(spans[2].count, 3, "assignment spans: variable + number + `=`")
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
