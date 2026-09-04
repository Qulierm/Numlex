import Foundation
import NumlexCore

/// r56: `weather in London` paints the city with exactly the existing
/// measurement-unit color.
///
/// The classifier assigns ONLY the meaningful place substring the
/// existing `.conversion` role (no weather/city role, no hardcoded
/// color); `in` takes the normal `.specifier` path and `weather`
/// stays base text. The range comes from the shared strict parser
/// (`WeatherQuery.placeRange`, nil exactly when `parse` is nil), so
/// parsing and highlighting share one grammar and cannot drift.
///
/// Coverage: exact UTF-16 range + role for London, flexible
/// outer/keyword spaces, multiword and comma places,
/// apostrophe/hyphen names, an accepted non-ASCII place,
/// emoji/surrogate rejection and boundary safety, `in` specifier +
/// weather base, invalid/incomplete/prose/comment/heading lines
/// painting no tails, sanitize bounds, and source guards proving the
/// role is literally `.conversion` flowing through the unit palette.

private func r56Spans(_ line: String) -> [SyntaxSpan] {
    SyntaxClassifier.spans(for: line, rates: Rates(), decimalPlaces: 7)[0]
}

private func r56Conversion(_ line: String) -> [NSRange] {
    r56Spans(line).filter { $0.role == .conversion }.map { $0.range }
}

public let r56Cases: [EngineCase] = [

    EngineCase("r56-city-london-exact") {
        // ONLY the city carries the unit role; `in` is a specifier.
        try expectEqual(r56Conversion("weather in London"),
                        [NSRange(location: 11, length: 6)], "city unit span")
        try expectEqual(r56Spans("weather in London")
            .filter { $0.role == .specifier }.map { $0.range },
            [NSRange(location: 8, length: 2)], "`in` specifier")
        // The role is literally the measurement-unit role.
        let roles = r56Spans("weather in London").map { $0.role }
        try expectEqual(roles.count, 2, "exactly two spans")
        try expectEqual(roles.filter { $0 == .conversion }.count, 1, "unit role")
        try expectEqual(roles.filter { $0 == .specifier }.count, 1, "specifier role")
    },

    EngineCase("r56-city-full-span-list") {
        // Sanitized order (location ascending): specifier, then city.
        try expectEqual(r56Spans("weather in London"),
                        [SyntaxSpan(role: .specifier,
                                    range: NSRange(location: 8, length: 2)),
                         SyntaxSpan(role: .conversion,
                                    range: NSRange(location: 11, length: 6))],
                        "exact span list")
    },

    EngineCase("r56-city-flexible-spaces") {
        // Outer and keyword whitespace excluded from the span.
        try expectEqual(r56Conversion("  weather   in   London  "),
                        [NSRange(location: 17, length: 6)], "outer/keyword spaces")
        try expectEqual(r56Spans("  weather   in   London  ")
            .filter { $0.role == .specifier }.map { $0.range },
            [NSRange(location: 12, length: 2)], "`in` after gaps")
        try expectEqual(r56Conversion("Weather In Paris"),
                        [NSRange(location: 11, length: 5)], "keyword case")
        try expectEqual(WeatherQuery.placeRange(in: "  weather   in   London  "),
                        NSRange(location: 17, length: 6), "parser agrees")
    },

    EngineCase("r56-city-multiword-comma") {
        // The full meaningful place, internal spaces and comma inside.
        try expectEqual(r56Conversion("weather in New York"),
                        [NSRange(location: 11, length: 8)], "multiword")
        try expectEqual(r56Conversion("weather in Paris, France"),
                        [NSRange(location: 11, length: 13)], "comma place")
    },

    EngineCase("r56-city-apostrophe-hyphen") {
        // Accepted name punctuation stays inside ONE unit span.
        try expectEqual(r56Conversion("weather in O'Fallon"),
                        [NSRange(location: 11, length: 8)], "straight apostrophe")
        try expectEqual(r56Conversion("weather in O’Fallon"),
                        [NSRange(location: 11, length: 8)], "curly apostrophe")
        try expectEqual(r56Conversion("weather in Aix-en-Provence"),
                        [NSRange(location: 11, length: 15)], "hyphenated whole")
        try expect(r56Spans("weather in Aix-en-Provence")
            .filter { $0.role == .operatorGlyph }.isEmpty,
            "hyphen never an operator", "hyphen")
    },

    EngineCase("r56-city-non-ascii") {
        // Accepted non-ASCII letters share the unit paint exactly.
        try expectEqual(r56Conversion("weather in S\u{E3}o Paulo"),
                        [NSRange(location: 11, length: 9)], "latin-1 range")
        try expectEqual(r56Conversion("weather in \u{5317}\u{4EAC}"),
                        [NSRange(location: 11, length: 2)], "CJK range")
    },

    EngineCase("r56-city-emoji-surrogate-rejected") {
        // Symbols/emoji are rejected: no unit paint anywhere.
        for line in ["weather in London😀",
                     "weather in Tokyo🗼",
                     "weather in 🇫🇷"] {
            try expect(WeatherQuery.parse(line) == nil, "rejected: \(line)", "parse")
            try expect(WeatherQuery.placeRange(in: line) == nil, "no range", "range")
            try expect(r56Conversion(line).isEmpty, "no unit paint: \(line)", "paint")
        }
        // Boundary: the parser walks grapheme clusters, so the decomposed
        // form (a + combining tilde) is accepted too — and the span is
        // still exact UTF-16 (9 characters, 10 code units).
        try expectEqual(WeatherQuery.placeRange(in: "weather in Sa\u{303}o Paulo"),
                        NSRange(location: 11, length: 10), "decomposed UTF-16 range")
        try expectEqual(r56Conversion("weather in Sa\u{303}o Paulo"),
                        [NSRange(location: 11, length: 10)], "decomposed paints exact")
    },

    EngineCase("r56-city-invalid-unpainted") {
        // Invalid/incomplete/prose/comment/heading/token lines never
        // paint arbitrary tails as units.
        for line in ["weather in",
                     "weather in   ",
                     "weather",
                     "weather today",
                     "weather inside London",
                     "weather in London + 5",
                     "weather in London - 5",
                     "the weather in London is nice",
                     "London is nice",
                     "// weather in London",
                     "# weather in London",
                     "weather in Lon￼don"] {
            try expect(r56Conversion(line).isEmpty, "no unit paint: '\(line)'", "paint")
        }
    },

    EngineCase("r56-city-sanitize-bounds") {
        // Every weather span is in-bounds and overlap-free (existing
        // sanitize), on valid and rejected lines alike.
        let lines = ["weather in London",
                     "weather in New York",
                     "weather in Paris, France",
                     "weather in O'Fallon",
                     "weather in São Paulo",
                     "weather in London + 5",
                     "the weather in London is nice"]
        for line in lines {
            let length = (line as NSString).length
            let spans = r56Spans(line)
            for s in spans {
                try expect(s.range.location >= 0 && s.range.length > 0 &&
                    NSMaxRange(s.range) <= length,
                    "in bounds: '\(line)'", "bounds")
            }
            for i in spans.indices {
                for j in spans.indices where j > i {
                    let inter = NSIntersectionRange(spans[i].range, spans[j].range)
                    try expect(inter.length == 0, "no overlap: '\(line)'", "overlap")
                }
            }
        }
    },

    EngineCase("r56-source-unit-role-mapping") {
        // The city flows through the EXISTING unit palette: classifier
        // emits literally `.conversion` from the shared parser range,
        // and the editor resolves that role through the configurable
        // unit color (custom Styling + Light/Dark follow live).
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        func src(_ rel: String) throws -> String {
            let url = root.appendingPathComponent(rel).standardizedFileURL
            guard let s = try? String(contentsOf: url, encoding: .utf8) else {
                throw CaseFailure(message: "missing \(rel)", location: "R56Cases")
            }
            return s
        }
        let syn = try src("Sources/NumlexCore/Engine/SyntaxHighlighting.swift")
        try expect(syn.contains("WeatherQuery.placeRange(in: line)"),
                   "range from shared parser", "shared")
        try expect(syn.contains("SyntaxSpan(role: .conversion, range: cityRange)"),
                   "city uses .conversion", "role")
        let editor = try src("Sources/NumlexApp/Editor/NotebookEditor.swift")
        try expect(editor.contains("case .conversion: palette.units"),
                   "editor maps unit role", "editor")
        let palette = try src("Sources/NumlexApp/NotebookPalette.swift")
        try expect(palette.contains("case .conversion: units"),
                   "palette owns unit color", "palette")
    },
]
