import Foundation
import NumlexCore

// MARK: - r21: operator / specifier / label role classification
//
// Operators and contextual syntax words are painted ONLY on lines the
// evaluator treats as math; prose, comments, headings and labels never
// receive them. Unit spans win over `/`, the answer-token marker U+FFFC
// is never painted, and every span stays inside the line's UTF-16
// bounds.

public let syntaxRoleCases: [EngineCase] = [
    EngineCase("role-operators-canonical-and-accepted") {
        // Canonical × ÷ − and accepted * / = all get the operator role.
        let s = SyntaxClassifier.spans(for: "2 × 3 ÷ 4 - 5 + 6 = 1",
                                       rates: Rates(), decimalPlaces: 7)[0]
        try expectEqual(s.filter { $0.role == .operatorGlyph }.map { $0.range },
                        [NSRange(location: 2, length: 1),
                         NSRange(location: 6, length: 1),
                         NSRange(location: 10, length: 1),
                         NSRange(location: 14, length: 1),
                         NSRange(location: 18, length: 1)],
                        "canonical and accepted glyphs")
        let star = SyntaxClassifier.spans(for: "3 * 4", rates: Rates(), decimalPlaces: 7)[0]
        try expectEqual(star.filter { $0.role == .operatorGlyph }.map { $0.range },
                        [NSRange(location: 2, length: 1)], "accepted *")
        let plus = SyntaxClassifier.spans(for: "1 + 2", rates: Rates(), decimalPlaces: 7)[0]
        try expectEqual(plus.filter { $0.role == .operatorGlyph }.map { $0.range },
                        [NSRange(location: 2, length: 1)], "canonical +")
    },
    EngineCase("role-operator-slash-loses-to-unit-span") {
        // The `/` inside `km/h` is unit content (the from-unit span is
        // longer and earlier, so sanitize keeps it); a free `1 / 2`
        // division keeps the operator glyph.
        let conv = SyntaxClassifier.spans(for: "10 km/h to meter",
                                          rates: Rates(), decimalPlaces: 7)[0]
        try expectEqual(conv.filter { $0.role == .conversion }.map { $0.range },
                        [NSRange(location: 3, length: 4),
                         NSRange(location: 11, length: 5)],
                        "km/h stays ONE unit span")
        try expectEqual(conv.filter { $0.role == .operatorGlyph }.count, 0,
                        "no operator inside a unit expression")
        let div = SyntaxClassifier.spans(for: "1 / 2", rates: Rates(), decimalPlaces: 7)[0]
        try expectEqual(div.filter { $0.role == .operatorGlyph }.map { $0.range },
                        [NSRange(location: 2, length: 1)], "free division keeps the operator")
    },
    EngineCase("role-operators-prose-exclusions") {
        // Prose, comments, headings and labels must NEVER receive
        // operator or specifier spans, wherever the glyphs occur.
        let prose = SyntaxClassifier.spans(for: "price + shipping = cost",
                                           rates: Rates(), decimalPlaces: 7)[0]
        try expectEqual(prose.count, 0, "plain prose untouched")
        let comment = SyntaxClassifier.spans(for: "// a + b to in per as",
                                             rates: Rates(), decimalPlaces: 7)[0]
        try expectEqual(comment.count, 0, "comment line untouched")
        let heading = SyntaxClassifier.spans(for: "# a + b × c",
                                             rates: Rates(), decimalPlaces: 7)[0]
        try expectEqual(heading.filter { $0.role == .operatorGlyph }.count, 0,
                        "heading body has no operator spans")
        try expectEqual(heading.count, 2, "marker + body only")
        // `Total - pending:` is prose with a trailing colon: label only.
        let label = SyntaxClassifier.spans(for: "Total - pending:",
                                           rates: Rates(), decimalPlaces: 7)[0]
        try expectEqual(label.filter { $0.role == .label }.count, 1,
                        "prose label line keeps its label")
        try expectEqual(label.filter { $0.role == .operatorGlyph }.count, 0,
                        "operators never painted on a label line")
        try expectEqual(label.filter { $0.role == .label }.first?.range,
                        NSRange(location: 0, length: 16), "whole trimmed line is the label")
    },
    EngineCase("role-specifiers-contextual-words") {
        // `to`/`in`/`per`/`as` are specifiers ONLY on conversion/natural
        // (math) lines — never in prose or identifiers.
        let conversion = SyntaxClassifier.spans(for: "10 km to meter",
                                                rates: Rates(), decimalPlaces: 7)[0]
        try expectEqual(conversion.filter { $0.role == .specifier }.map { $0.range },
                        [NSRange(location: 6, length: 2)], "`to` in a conversion")
        let inConv = SyntaxClassifier.spans(for: "100 km in miles",
                                            rates: Rates(), decimalPlaces: 7)[0]
        try expectEqual(inConv.filter { $0.role == .specifier }.map { $0.range },
                        [NSRange(location: 7, length: 2)], "`in` in a conversion")
        // `per` in a natural money line.
        let natural = SyntaxClassifier.spans(for: "food = $50 per day",
                                             rates: Rates(), decimalPlaces: 7)[0]
        try expectEqual(natural.filter { $0.role == .specifier }.map { $0.range },
                        [NSRange(location: 11, length: 3)], "`per` in a natural line")
        // Prose and identifiers never match.
        let prose = SyntaxClassifier.spans(for: "to be or not to be",
                                           rates: Rates(), decimalPlaces: 7)[0]
        try expectEqual(prose.count, 0, "prose `to` unspanned")
        let ident = SyntaxClassifier.spans(for: "total = 5",
                                           rates: Rates(), decimalPlaces: 7)[0]
        try expectEqual(ident.filter { $0.role == .specifier }.count, 0,
                        "identifier containing `to` is not a specifier")
    },
    EngineCase("role-label-trailing-colon") {
        let colon = SyntaxClassifier.spans(for: "Total expenses:", rates: Rates(), decimalPlaces: 7)[0]
        try expectEqual(colon.map { $0.role }, [.label], "whole prose line is a label")
        try expectEqual(colon[0].range, NSRange(location: 0, length: 15), "full line range")
        let indented = SyntaxClassifier.spans(for: "  Note:  ", rates: Rates(), decimalPlaces: 7)[0]
        try expectEqual(indented[0].range, NSRange(location: 2, length: 5),
                        "trimmed range, no surrounding whitespace")
        let noColon = SyntaxClassifier.spans(for: "plain prose", rates: Rates(), decimalPlaces: 7)[0]
        try expectEqual(noColon.count, 0, "prose without colon unspanned")
        let midColon = SyntaxClassifier.spans(for: "note: no trailing colon",
                                              rates: Rates(), decimalPlaces: 7)[0]
        try expectEqual(midColon.count, 0, "mid-line colon is not a label")
        // Evaluated lines are NEVER labels: `x:` alone is skip prose, but
        // `5 + 1` evalutes and its `+` is an operator, not a label.
        let evaluated = SyntaxClassifier.spans(for: "x = 5", rates: Rates(), decimalPlaces: 7)[0]
        try expectEqual(evaluated.filter { $0.role == .label }.count, 0,
                        "assignment is not a label")
    },
    EngineCase("role-operator-never-paints-answer-token") {
        // The answer-token marker U+FFFC must never receive an operator
        // (or any other) span, and lines around it stay in bounds.
        let tokenLine = SyntaxClassifier.spans(
            for: "3 + \u{FFFC}", rates: Rates(), decimalPlaces: 7)[0]
        for span in tokenLine {
            try expect(NSMaxRange(span.range) <= 5, "span inside the line")
            try expect(!span.range.contains(4), "marker position never spanned")
        }
        // Ranges are UTF-16-clean on a mixed line.
        let mixed = SyntaxClassifier.spans(for: "выплата = 1 + 2",
                                           rates: Rates(), decimalPlaces: 7)[0]
        try expectEqual(mixed.filter { $0.role == .operatorGlyph }.map { $0.range },
                        [NSRange(location: 8, length: 1),
                         NSRange(location: 12, length: 1)], "UTF-16 operator offsets")
    },
    EngineCase("role-malformed-input-stays-bounded") {
        // Sanitizing keeps every span inside the line whatever the input.
        let empty = SyntaxClassifier.spans(for: "", rates: Rates(), decimalPlaces: 7)[0]
        try expectEqual(empty.count, 0, "empty line has no spans")
        let blank = SyntaxClassifier.spans(for: "   ", rates: Rates(), decimalPlaces: 7)[0]
        try expectEqual(blank.count, 0, "whitespace-only line has no spans")
        let trailingColon = SyntaxClassifier.spans(for: ": ", rates: Rates(), decimalPlaces: 7)[0]
        try expectEqual(trailingColon.map { $0.role }, [.label], "bare colon line is a label")
        try expectEqual(trailingColon[0].range, NSRange(location: 0, length: 1),
                        "colon only, no whitespace")
        // Surrogate pairs (emoji) never break UTF-16 span math.
        let emoji = SyntaxClassifier.spans(for: "🎉 = 5", rates: Rates(), decimalPlaces: 7)[0]
        for span in emoji {
            try expect(span.range.location >= 0 && NSMaxRange(span.range) <= 6,
                       "emoji line spans in bounds")
        }
    },
    EngineCase("role-comment-and-heading-keep-existing-roles") {
        let heading = SyntaxClassifier.spans(for: "# Result", rates: Rates(), decimalPlaces: 7)[0]
        try expectEqual(heading.map { $0.role }, [.hashMarker, .hashBody])
        try expectEqual(heading[1].range, NSRange(location: 1, length: 7), "body range")
        // `//` without a space still skips token spans (comment prefix).
        let tight = SyntaxClassifier.spans(for: "//x + 1", rates: Rates(), decimalPlaces: 7)[0]
        try expectEqual(tight.count, 0, "tight comment unspanned")
    },
]