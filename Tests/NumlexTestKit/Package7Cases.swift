import Foundation
import NumlexCore

// MARK: - Package 7: shared sheet-line grammar (tags, dividers, headings)

private func p7rows(_ source: String) -> [SheetLine] {
    var vars: [String: Double] = [:]
    return evaluateSheet(source, variables: &vars, rates: Rates(), decimalPlaces: 7)
}

public let package7Cases: [EngineCase] = [

    EngineCase("p7-heading-requires-hash-space") {
        let rows = p7rows("# Head\n#food\n#\n# tagless\nis #tag")
        try expectEqual(rows.count, 5, "one row per line")
        try expectEqual(SheetLineAnalysis.parse("# Head").kind, .heading)
        // A tagged `#food` line is TAG-ONLY (quiet blank), never heading.
        let tagOnly = SheetLineAnalysis.parse("#food")
        try expectEqual(tagOnly.kind, .tagOnly)
        try expectEqual(tagOnly.tags.map(\.key), ["food"])
        try expectEqual(rows[1].result, .blank, "tag-only line is quiet")
        // A lone `#` is ordinary prose (skip), never a heading.
        try expectEqual(SheetLineAnalysis.parse("#").kind, .expression)
        try expectEqual(rows[2].result, .skip, "lone hash is prose")
        // `# ` heading body keeps its text.
        try expectEqual(SheetLineAnalysis.parse("# Head").headingBodySpan,
                        NSRange(location: 2, length: 4))
    },

    EngineCase("p7-tag-suffix-grammar") {
        // Multiple whitespace-separated tags at the end.
        let multi = SheetLineAnalysis.parse("2 + 3 #math #cash")
        try expectEqual(multi.kind, .expression)
        try expectEqual(multi.tags.map(\.key), ["math", "cash"])
        try expectEqual(multi.evaluationProjection, "2 + 3")
        try expectEqual(multi.tagSuffixSpan, NSRange(location: 6, length: 11))
        // Duplicates dedupe (first spelling wins).
        let dup = SheetLineAnalysis.parse("x = 1 #a #A")
        try expectEqual(dup.tags.map(\.key), ["a"])
        try expectEqual(dup.tags.map(\.spelling), ["a"])
        // `2 #food + 3` is NOT a tag suffix (trailing token is `3`).
        let notTag = SheetLineAnalysis.parse("2 #food + 3")
        try expect(notTag.tags.isEmpty, "non-terminal hash is not a tag")
        try expectEqual(notTag.evaluationProjection, "2 #food + 3")
        // Identifier rules: must start with a letter; letters, digits,
        // `_` and `-` after that.
        for bad in ["#1abc", "#", "#a b", "#-lead", "#\u{301}x"] {
            let parsed = SheetLineAnalysis.parse(bad)
            try expect(parsed.tags.isEmpty, "\(bad) is not a tag")
        }
        for good in ["#a", "#A_1", "#café", "#tag-name", "#tagName2"] {
            let parsed = SheetLineAnalysis.parse(good)
            try expectEqual(parsed.tags.count, 1, "\(good) is a tag")
        }
        // Unicode normalization + case-insensitive key, source spelling
        // preserved.
        let nfc = SheetLineAnalysis.parse("1 #café")
        try expectEqual(nfc.tags[0].key, "café")
        try expectEqual(nfc.tags[0].spelling, "café")
        // 64-grapheme bound.
        let long = String(repeating: "a", count: 65)
        try expect(SheetLineAnalysis.parse("1 #\(long)").tags.isEmpty,
                   "over-long identifier is not a tag")
        try expectEqual(SheetLineAnalysis.parse("1 #\(String(repeating: "a", count: 64))")
            .tags.count, 1)
        // Headings and comments never declare tags.
        try expect(SheetLineAnalysis.parse("# h #tag").tags.isEmpty, "heading no tags")
        try expect(SheetLineAnalysis.parse("// c #tag").tags.isEmpty, "comment no tags")
    },

    EngineCase("p7-tags-never-change-the-answer") {
        let rows = p7rows("base = 10\nbase + 5 #sum #report\ntotal of nothing")
        try expectEqual(rows[1].result, .number(value: 15, unit: nil,
                                                kind: .plain, fraction: nil),
                        "tagged expression evaluates its body")
        // A tagged declaration declares normally.
        try expectEqual(rows[0].result, .variable(name: "base", value: 10,
                                                  kind: .plain, fraction: nil))
        // Bare token lines with tags keep resolving (covered in resolve
        // tests); here at least the projection is the marker-only body.
        let marker = SheetLineAnalysis.parse("\u{FFFC} #link")
        try expectEqual(marker.evaluationProjection, "\u{FFFC}")
        try expectEqual(marker.tags.map(\.key), ["link"])
    },

    EngineCase("p7-divider-exactness-and-metadata") {
        try expectEqual(SheetLineAnalysis.parse("---").kind, .divider)
        try expectEqual(SheetLineAnalysis.parse("  ---  ").kind, .divider)
        try expectEqual(SheetLineAnalysis.parse("----").kind, .expression,
                        "four dashes are ordinary")
        try expectEqual(SheetLineAnalysis.parse("—").kind, .expression)
        let rows = p7rows("1 + 1\n---\n2 + 2")
        try expectEqual(rows[1].result, .blank, "divider has no answer")
        try expectEqual(rows[1].metadata, .divider, "divider metadata")
        try expect(SheetFooterTotal.aggregate(rows) == 6,
                   "divider contributes nothing; 1+1 + 2+2")
        // `----` is an ordinary visible row (skip for prose-like dashes).
        let four = p7rows("----")
        try expectEqual(four[0].metadata, .ordinary, "four dashes ordinary")
        // Divider spans for styling.
        try expectEqual(SheetLineAnalysis.parse("  ---  ").dividerSpan,
                        NSRange(location: 2, length: 3))
    },

    EngineCase("p7-classifier-tag-and-divider-spans") {
        let spans = SyntaxClassifier.spans(for: "2 + 3 #math #cash\n---\n# Head",
                                           rates: Rates(), decimalPlaces: 7)
        let tags = spans[0].filter { $0.role == .tagMarker || $0.role == .tagBody }
        try expectEqual(tags.count, 4, "two tags, marker + body each")
        try expectEqual(tags[0].role, .tagMarker)
        try expectEqual(tags[0].range, NSRange(location: 6, length: 1))
        try expectEqual(tags[1].role, .tagBody)
        try expectEqual(tags[1].range, NSRange(location: 7, length: 4))
        try expectEqual(spans[1].map(\.role), [.divider])
        try expectEqual(spans[1][0].range, NSRange(location: 0, length: 3))
        try expectEqual(spans[2].map(\.role), [.hashMarker, .hashBody])
        try expectEqual(spans[2][0].range, NSRange(location: 0, length: 2))
    },

    EngineCase("p7-weather-scan-ignores-tag-suffix") {
        // A trailing tag must never become part of a place name.
        let queries = WeatherQuery.scanQueries(in: "weather in Paris #travel")
        try expectEqual(queries.count, 1)
        try expect(queries[0].display.lowercased().contains("paris"),
                   "place name stays Paris")
        try expect(!queries[0].display.contains("#"),
                   "no tag hash in the place name")
    },
]
