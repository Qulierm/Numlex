import Foundation
import NumlexCore

/// Focused cases for the `×` operator and the pure notebook math
/// formatter. Ranges/maps are UTF-16 offsets inside the line under test.
public let formatCases: [EngineCase] = [
    EngineCase("format-multiplication-sign") {
        try expectEqual(NotebookFormatting.canonicalMathText("12+30*2"),
                        "12 + 30 × 2", "ASCII * becomes spaced ×")
        try expectEqual(NotebookFormatting.canonicalMathText("12 + 30 * 2"),
                        "12 + 30 × 2", "spaced * canonicalizes too")
        // Evaluate both forms identically.
        var v: [String: Double] = [:]
        let a = evalLine("12+30*2", variables: &v, rates: Rates(), decimalPlaces: 7)
        var v2: [String: Double] = [:]
        let b = evalLine("12 + 30 × 2", variables: &v2, rates: Rates(), decimalPlaces: 7)
        guard case .number(let av, nil) = a, case .number(let bv, nil) = b else {
            throw CaseFailure(message: "× expression must evaluate", location: "FormatCases")
        }
        try expectEqual(av, 72.0, "12+30*2")
        try expectEqual(bv, 72.0, "12 + 30 × 2")
    },

    EngineCase("format-assignment-and-variables") {
        try expectEqual(NotebookFormatting.canonicalMathText("x=5"), "x = 5")
        try expectEqual(NotebookFormatting.canonicalMathText("x =5"), "x = 5")
        try expectEqual(NotebookFormatting.canonicalMathText("x * 3"), "x × 3")
        try expectEqual(NotebookFormatting.canonicalMathText("x*-2"), "x × -2")
        var v: [String: Double] = [:]
        _ = evalLine("x = 5", variables: &v, rates: Rates(), decimalPlaces: 7)
        let r = evalLine("x × -2", variables: &v, rates: Rates(), decimalPlaces: 7)
        guard case .number(let val, nil) = r else { throw CaseFailure(message: "x × -2 must evaluate", location: "FormatCases") }
        try expectEqual(val, -10.0, "x = 5, x × -2")
    },

    EngineCase("format-unary-stays-attached") {
        try expectEqual(NotebookFormatting.canonicalMathText("-(2+3)"), "-(2 + 3)")
        try expectEqual(NotebookFormatting.canonicalMathText("-5"), "-5")
        try expectEqual(NotebookFormatting.canonicalMathText("- 5"), "-5")
        try expectEqual(NotebookFormatting.canonicalMathText("5 - 3"), "5 - 3")
        try expectEqual(NotebookFormatting.canonicalMathText("5-3"), "5 - 3")
        try expectEqual(NotebookFormatting.canonicalMathText("x = -5"), "x = -5")
    },

    EngineCase("format-percent-and-parens") {
        try expectEqual(NotebookFormatting.canonicalMathText("50%"), "50%")
        try expectEqual(NotebookFormatting.canonicalMathText("50 %"), "50%")
        try expectEqual(NotebookFormatting.canonicalMathText("2(3)"), "2(3)")
        try expectEqual(NotebookFormatting.canonicalMathText("2 (3)"), "2 (3)")
        try expectEqual(NotebookFormatting.canonicalMathText("2*(3+4)*2"), "2 × (3 + 4) × 2")
        try expectEqual(NotebookFormatting.canonicalMathText("(2+3)"), "(2 + 3)")
        try expectEqual(NotebookFormatting.canonicalMathText(" ( 2 + 3 ) "), " (2 + 3)", "indent kept, inside-paren spaces dropped")
    },

    EngineCase("format-idempotence-and-whitespace") {
        try expectEqual(NotebookFormatting.canonicalMathText("12 + 30 × 2"),
                        "12 + 30 × 2", "already canonical")
        try expectEqual(NotebookFormatting.canonicalMathText("12   +    30  * 2"),
                        "12 + 30 × 2", "redundant whitespace collapses")
        try expectEqual(NotebookFormatting.canonicalMathText("1,234+5"), "1,234 + 5", "thousands separator token")
        try expectEqual(NotebookFormatting.canonicalMathText("2.5k × 2"), "2.5k × 2", "decimal + suffix")
    },

    EngineCase("format-non-math-lines-untouched") {
        let docs: [(String, String)] = [
            ("shopping list", "shopping list"),
            ("# comment * here", "# comment * here"),
            ("// Title * here", "// Title * here"),
            ("", ""),
            ("10 cm to m", "10 cm to m"),
            ("hyphenated note - 2024", "hyphenated note - 2024"),
            ("значение x", "значение x")
        ]
        for (input, expected) in docs {
            try expectEqual(NotebookFormatting.canonicalDocument(input), expected, input)
        }
    },

    EngineCase("format-multiline-mixed") {
        let input = "shopping list\n12+30*2\nx=5\nx * 3\n10 km to m\n# keep * as is\n\n50 % + 2(3)"
        let expected = "shopping list\n12 + 30 × 2\nx = 5\nx × 3\n10 km to m\n# keep * as is\n\n50% + 2(3)"
        try expectEqual(NotebookFormatting.canonicalDocument(input), expected, "mixed document")
        // The tricky line is idempotent once canonical.
        try expectEqual(NotebookFormatting.canonicalMathText("50% + 2(3)"),
                        "50% + 2(3)", "idempotent")
    },

    EngineCase("format-caret-map") {
        // "12+3" -> "12 + 3": insertion points must map to the same
        // semantic positions in the canonical text.
        guard let r = NotebookFormatting.canonicalLine("12+3") else {
            throw CaseFailure(message: "12+3 is mathematical", location: "FormatCases")
        }
        try expectEqual(r.text, "12 + 3")
        try expectEqual(r.map.count, 5, "map covers 0...4")
        try expectEqual(r.map[0], 0, "start stays at start")
        try expectEqual(r.map[3], 4, "caret between + and 3 maps after the operator space")
        try expectEqual(r.map[4], 6, "end maps to end")
        // Identity for unchanged lines.
        guard let r2 = NotebookFormatting.canonicalLine("12 + 3") else {
            throw CaseFailure(message: "canonical line must stay mathematical", location: "FormatCases")
        }
        try expectEqual(r2.map[2], 2, "mid-line identity")
        // Trailing operator keeps its space and the caret maps past it:
        // "12+" -> "12 +" with the caret at the very end.
        guard let r3 = NotebookFormatting.canonicalLine("12+") else {
            throw CaseFailure(message: "incomplete expression is mathematical", location: "FormatCases")
        }
        try expectEqual(r3.text, "12 +")
        try expectEqual(r3.map[3], 4, "caret stays at the end after the operator space")
    },

    EngineCase("format-document-caret-map") {
        // Multiline documents used to double-count the newline insertion
        // point, shifting every later caret by one and scrambling fast
        // typing. The map must cover exactly 0...count(from) positions.
        let from = "\nx="
        let to = "\nx ="
        let map = NotebookFormatting.mapDocument(from: from, to: to)
        try expectEqual(map.count, (from as NSString).length + 1, "map length")
        try expectEqual(map[0], 0, "document start")
        try expectEqual(map[1], 1, "start of second line")
        try expectEqual(map[3], 4, "caret after '=' lands after the spaced '='")
        // Typing through a growing multiline document, caret always at
        // the end of the current text.
        let grow1 = "12+30\nx*"
        let canon1 = NotebookFormatting.canonicalDocument(grow1)
        let map1 = NotebookFormatting.mapDocument(from: grow1, to: canon1)
        try expectEqual(map1.count, (grow1 as NSString).length + 1, "map1 length")
        try expectEqual(map1[grow1.count], (canon1 as NSString).length, "end maps to end")
        // Trailing newline document: from "\n" to "\n" is identity.
        let map2 = NotebookFormatting.mapDocument(from: "\n", to: "\n")
        try expectEqual(map2, [0, 1], "identity trailing newline")
        // A blank line between formatted lines keeps every caret stable.
        let map3 = NotebookFormatting.mapDocument(from: "12+3\n\n45+6", to: "12 + 3\n\n45 + 6")
        try expectEqual(map3.count, ("12+3\n\n45+6" as NSString).length + 1, "map3 length")
        try expectEqual(map3[6], 8, "caret at start of third line lands after the blank line")
        try expectEqual(map3[10], 14, "caret at document end maps to end")
    },

    EngineCase("localization-new-sheet-label") {
        try expectEqual(L10n.t("newSheet", language: .en), "New Sheet",
                        "exact English label")
        try expectEqual(L10n.t("newSheet", language: .ru), "Новый лист", "ru")
        try expectEqual(L10n.t("newSheet", language: .de), "Neues Blatt", "de")
        try expectEqual(L10n.t("newSheet", language: .fr), "Nouvelle feuille", "fr")
        try expectEqual(L10n.t("newSheet", language: .it), "Nuovo foglio", "it")
        try expectEqual(L10n.t("newSheet", language: .zh), "新建工作表", "zh")
    },

    EngineCase("format-x-evaluation-equivalence") {
        let pairs: [(String, Double)] = [
            ("2 × 3", 6),
            ("12 × 30 × 2", 720),
            ("2 × (3 + 4) × 2", 28),
            ("100 × 1.5", 150),
            ("7 / 2", 3.5),
            ("2 ^ 3", 8)
        ]
        for (expr, expected) in pairs {
            var v: [String: Double] = [:]
            guard case .number(let value, nil)? = evalLine(expr, variables: &v, rates: Rates(), decimalPlaces: 7) else {
                throw CaseFailure(message: "\(expr) must evaluate", location: "FormatCases")
            }
            try expectEqual(value, expected, expr)
        }
    }
]
