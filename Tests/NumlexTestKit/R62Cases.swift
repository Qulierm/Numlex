import Foundation
import NumlexCore

/// r62: answer double-click token minting — regression coverage.
///
/// The r62 incident: after window resizes (widening, compact heights,
/// zoom), the AppKit hit surface of the answer wheel-catcher could
/// desync from the SwiftUI layout that positions the visible answer
/// ink. Double-clicks on the ink then landed in a dead zone: no
/// mousedown ever reached the catcher, so no token was minted on ANY
/// answer row. The repair:
///   1. the catcher's SwiftUI frame is explicitly pinned to the
///      GeometryReader's exact content region (width AND height,
///      top-leading) instead of relying on the representable's
///      unspecified ideal size;
///   2. `WheelView.layout()` re-syncs the NSView to its hosting
///      wrapper on EVERY layout pass, so a stale frame can never
///      survive a reflow.
/// The pure logic (pair semantics, token plans for every mintable
/// row kind, duplicate/selection handling) and the layout invariants
/// are pinned below.

private let WM = "\u{FFFC}"

/// Repo-root-relative source read. The compiler may bake `#file` in as a
/// RELATIVE path (relative to the package root at build time), which a
/// later cwd resolves against the wrong directory — so the repo root is
/// established two ways: walking up from the compiled location, and
/// walking up from the runner's cwd until the kit file itself is found.
private func r62Source(_ path: String) -> String {
    let fm = FileManager.default
    let marker = "Tests/NumlexTestKit/R62Cases.swift"
    var roots: [String] = []
    let fromFile = URL(fileURLWithPath: #file)
        .deletingLastPathComponent()      // Tests/NumlexTestKit
        .deletingLastPathComponent()      // Tests
        .deletingLastPathComponent()      // repo root
    roots.append(fromFile.path)
    var dir = URL(fileURLWithPath: fm.currentDirectoryPath)
    for _ in 0..<10 {
        roots.append(dir.path)
        guard dir.path != "/" else { break }
        dir = dir.deletingLastPathComponent()
    }
    for root in roots {
        let markerURL = URL(fileURLWithPath: root).appendingPathComponent(marker)
        guard fm.fileExists(atPath: markerURL.path) else { continue }
        let target = URL(fileURLWithPath: root).appendingPathComponent(path)
        guard let text = try? String(contentsOf: target, encoding: .utf8) else { continue }
        return text
    }
    return ""
}

/// Plans a token on `sourceLineIndex` with a collapsed caret at
/// `caret`, over the sheet's own 1:1 line IDs.
private func r62Plan(_ content: String,
                     sourceLineIndex: Int,
                     caret: Int = 0,
                     length: Int = 0,
                     refs: [AnswerReference] = [],
                     weather: WeatherContext = .empty)
-> (plan: AnswerTokenInsertion.Plan?, lines: [SheetLine]) {
    let ids = content.split(separator: "\n", omittingEmptySubsequences: false)
        .map { _ in UUID() }
    var v: [String: Double] = [:]
    let lines = evaluateSheet(content, variables: &v, rates: Rates(),
                              decimalPlaces: 7, weather: weather)
    let plan = AnswerTokenInsertion.plan(
        content: content, lineIDs: ids, references: refs,
        sourceLineIndex: sourceLineIndex,
        selection: NSRange(location: caret, length: length))
    return (plan, lines)
}

public let r62Cases: [EngineCase] = [
    // MARK: click-count pair semantics (the r44 invariant, unchanged)

    EngineCase("r62-click-count-pairs") {
        try expect(!AnswerDoubleClick.completesPair(at: 1),
                   "a pair start (odd) never fires")
        try expect(AnswerDoubleClick.completesPair(at: 2),
                   "count 2 completes the first pair")
        try expect(!AnswerDoubleClick.completesPair(at: 3),
                   "count 3 is a new pair start")
        try expect(AnswerDoubleClick.completesPair(at: 4),
                   "count 4 completes the second pair of an unbroken run")
        try expect(!AnswerDoubleClick.completesPair(at: 5), "odd never fires")
        try expect(AnswerDoubleClick.completesPair(at: 6),
                   "count 6 completes the third pair")
        try expect(!AnswerDoubleClick.completesPair(at: 0),
                   "no click never fires")
        try expect(!AnswerDoubleClick.completesPair(at: -2),
                   "a negative count never fires")
    },

    // MARK: token plans for every mintable row kind

    EngineCase("r62-mint-number-row") {
        // The caret sits on the (blank) line 2 (cross-line: the r80
        // same-line branch mints on a new line below the source).
        let content = "1+1\n"
        let (plan, lines) = r62Plan(content, sourceLineIndex: 0, caret: 4)
        guard case .number(let v, let u) = lines[0].result, u == nil, v == 2
        else { return try expect(false, "sanity: 1+1 is a unitless number") }
        guard let plan else { return try expect(false, "number row plans a token") }
        try expectEqual(plan.content, content + WM,
                        "the marker is inserted at the line-2 caret; the source is untouched")
        try expectEqual(plan.caret, 5, "the caret lands right after the marker")
        try expectEqual(plan.references.count, 1, "exactly one fresh reference")
        try expectEqual(plan.newReference.labelLine, 1,
                        "the token keeps the 1-based source label")
    },

    EngineCase("r62-mint-variable-row") {
        // Caret on the (blank) line 2, source line 1 (cross-line).
        let content = "apple = 5\n"
        let (plan, lines) = r62Plan(content, sourceLineIndex: 0, caret: 10)
        guard case .variable = lines[0].result
        else { return try expect(false, "sanity: assignment is a variable row") }
        guard let plan else { return try expect(false, "variable row plans a token") }
        try expect(plan.content.contains(WM), "marker inserted")
        try expectEqual(plan.caret, 11, "caret after the marker")
    },

    EngineCase("r62-mint-money-row") {
        let content = "$10 + 5% tip\n"
        let (plan, lines) = r62Plan(content, sourceLineIndex: 0, caret: 13)
        guard case .money = lines[0].result
        else { return try expect(false, "sanity: money row kind") }
        guard let plan else { return try expect(false, "money row plans a token") }
        try expectEqual(plan.content, content + WM, "marker at the line-2 caret")
    },

    EngineCase("r62-mint-unit-row") {
        let content = "10 km in m\n"
        let (plan, lines) = r62Plan(content, sourceLineIndex: 0, caret: 11)
        guard case .number(_, let u) = lines[0].result, u != nil
        else { return try expect(false, "sanity: conversion row carries a unit") }
        guard let plan else { return try expect(false, "unit row plans a token") }
        try expectEqual(plan.content, content + WM, "marker at the line-2 caret")
        try expectEqual(plan.newReference.labelLine, 1, "stable source label")
    },

    EngineCase("r62-mint-weather-row") {
        // Weather answers are unit-bearing numbers (C°) — minted exactly
        // like any number row; the token re-resolves the live value.
        // A snapshot context stands in for the live service (r55 style):
        // the mint path is identical regardless of value source.
        let content = "weather in London\n"
        let weather = WeatherContext(snapshots: ["london": WeatherSnapshot(
            queryKey: "london", displayQuery: "London",
            placeName: "London", country: "United Kingdom",
            latitude: 51.5074, longitude: -0.1278,
            temperatureCelsius: 18.5, fetchedAt: Date())])
        let (plan, lines) = r62Plan(content, sourceLineIndex: 0, caret: 18, weather: weather)
        guard case .number(_, let u) = lines[0].result, u != nil
        else { return try expect(false, "sanity: weather row is a unit number") }
        guard let plan else { return try expect(false, "weather row plans a token") }
        try expectEqual(plan.content, content + WM, "marker at the line-2 caret")
    },

    EngineCase("r62-mint-inline-total-row") {
        let content = "10\n20\ntotal\n"
        let (plan, lines) = r62Plan(content, sourceLineIndex: 2, caret: 12)
        guard case .number = lines[2].result, lines[2].isTotal
        else { return try expect(false, "sanity: total is a number row flagged isTotal") }
        guard let plan else { return try expect(false, "total row plans a token") }
        try expectEqual(plan.content, content + WM,
                        "the total token inserts at the line-4 caret without disturbing the sheet")
        try expectEqual(plan.newReference.labelLine, 3,
                        "the total keeps its 1-based label")
    },

    // MARK: duplicates, selection replacement, refusals

    EngineCase("r62-duplicate-tokens-same-source") {
        // Both tokens land on the (blank) line 2 (cross-line).
        let content = "1+1\n\n"
        let ids = [UUID(), UUID(), UUID()]
        guard let first = AnswerTokenInsertion.plan(
            content: content, lineIDs: ids, references: [],
            sourceLineIndex: 0,
            selection: NSRange(location: 4, length: 0))
        else { return try expect(false, "first token plans on line 2") }
        guard let second = AnswerTokenInsertion.plan(
            content: first.content, lineIDs: first.lineIDs,
            references: first.references,
            sourceLineIndex: 0,
            selection: NSRange(location: 5, length: 0))
        else { return try expect(false, "second token on the same source plans") }
        try expectEqual(second.references.count, 2,
                        "two tokens from one source line coexist")
        let markers = second.content.unicodeScalars
            .filter { $0.value == 0xFFFC }.count
        try expectEqual(markers, 2, "one marker per token")
    },

    EngineCase("r62-selection-replaced-by-single-marker") {
        // r77c: the selection is on line 2 (source = line 1).
        let content = "1+1\nabc\n"
        let ids = [UUID(), UUID(), UUID()]
        guard let plan = AnswerTokenInsertion.plan(
            content: content, lineIDs: ids, references: [],
            sourceLineIndex: 0,
            selection: NSRange(location: 4, length: 3))
        else { return try expect(false, "selection replacement plans") }
        try expectEqual(plan.content, "1+1\n" + WM + "\n",
                        "the selected text is replaced by the single marker")
        try expectEqual(plan.caret, 5, "caret after the replacement")
    },

    EngineCase("r62-cross-line-selection-refused") {
        let content = "1+1\n2+2\n"
        let ids = [UUID(), UUID(), UUID()]
        let plan = AnswerTokenInsertion.plan(
            content: content, lineIDs: ids, references: [],
            sourceLineIndex: 0,
            selection: NSRange(location: 1, length: 4))  // crosses "\n"
        try expect(plan == nil,
                   "a selection crossing a newline would merge lines — deterministically refused")
    },

    EngineCase("r62-out-of-bounds-selection-refused") {
        let content = "1+1"
        let ids = [UUID()]
        let plan = AnswerTokenInsertion.plan(
            content: content, lineIDs: ids, references: [],
            sourceLineIndex: 0,
            selection: NSRange(location: 4, length: 0))
        try expect(plan == nil, "a caret past the end is a no-op")
    },

    // MARK: the r62 layout repair — pinned in source

    EngineCase("r62-catcher-frame-pinned-to-region") {
        let view = r62Source("Sources/NumlexApp/Views/AnswerColumnView.swift")
        try expect(view.contains("height: geo.size.height"),
                   "the catcher frame pins the region HEIGHT, not just width")
        try expect(view.contains("alignment: .topLeading"),
                   "the catcher frame is top-leading anchored to the region")
        try expect(view.contains(".allowsHitTesting(true)"),
                   "the catcher is the top interaction layer of the answer column")
    },

    EngineCase("r62-wheelview-bounds-selfsync") {
        let view = r62Source("Sources/NumlexApp/Views/AnswerColumnView.swift")
        try expect(view.contains("override func layout()"),
                   "WheelView re-syncs on every layout pass")
        try expect(view.contains("frame = sup.bounds"),
                   "the NSView always fills its SwiftUI hosting wrapper, so a stale frame can never detach the hit surface from the visible answers after a resize")
    },

    EngineCase("r62-divider-and-hover-stay-inert") {
        let view = r62Source("Sources/NumlexApp/Views/AnswerColumnView.swift")
        // Anchor on the code occurrence (the Color layer), not the
        // earlier documentation comment that also names the token.
        let divider = view.range(of: "Color(nsColor: Design.panelSeparator)")
        try expect(divider != nil, "the r58 total-divider layer is present")
        if let d = divider {
            try expect(view[d.lowerBound...].prefix(300).contains("allowsHitTesting(false)"),
                       "the divider layer never participates in hit testing")
        }
        try expect(view.contains("AnswerHoverOutline"),
                   "the r37 hover outline layer is present")
    },

    EngineCase("r62-mint-switch-kinds") {
        let view = r62Source("Sources/NumlexApp/Views/AnswerColumnView.swift")
        let block = view.range(of: "onDoubleTap: { y, count in")
            .map { String(view[$0.lowerBound..<view.endIndex]).prefix(1800) } ?? ""
        try expect(block.contains("case .number, .variable, .money"),
                   "double-tap mints number/variable/money rows (number covers units and weather)")
        try expect(!block.contains(".date"),
                   "date answers are never minted")
    },

    EngineCase("r62-ime-and-bridge-noop-policy") {
        let editor = r62Source("Sources/NumlexApp/Editor/NotebookEditor.swift")
        try expect(editor.contains("hasMarkedText()"),
                   "a live IME composition makes the selection snapshot nil — minting is a deterministic no-op, never a mid-composition insertion")
        let content = r62Source("Sources/NumlexApp/Views/ContentView.swift")
        try expect(content.contains("selectionSnapshot(sheetID: sheetID)"),
                   "a stale or missing bridge yields a no-op; nothing is ever appended as a fallback")
    },

    // MARK: r80 — a same-line click mints the token on a NEW line

    EngineCase("r77c-same-line-mints-below") {
        // r80 supersedes the r77c refusal: a collapsed caret anywhere ON
        // the source line mints the token on a NEW line immediately
        // after the source — "7×8\n" becomes "7×8\nM\n" (the existing
        // blank line is preserved after the new one).
        let content = "7×8\n"
        for caret in [0, 1, 2, 3] {
            let (plan, _) = r62Plan(content, sourceLineIndex: 0, caret: caret)
            guard let plan else {
                return try expect(false, "same-line caret \(caret): the r80 branch must plan")
            }
            try expectEqual(plan.content, content + WM + "\n",
                            "same-line caret \(caret): marker on its own new line after the source")
            try expectEqual(plan.caret, 5, "the caret lands right after the marker (unit 4)")
            try expectEqual(plan.newReference.sourceLineID, plan.lineIDs[0],
                            "the fresh reference points at the source line's stable ID")
            try expect(plan.lineIDs.count == 3 && plan.lineIDs[1] != plan.lineIDs[0] && plan.lineIDs[1] != plan.lineIDs[2],
                       "a fresh ID was minted for the new marker line")
        }
        // A contained non-empty selection on the source line is planned
        // the same way — the source text is preserved, the marker goes
        // below.
        let (sel, _) = r62Plan(content, sourceLineIndex: 0, caret: 1, length: 2)
        guard let sel else {
            return try expect(false, "same-line selection: the r80 branch must plan")
        }
        try expectEqual(sel.content, content + WM + "\n", "source preserved, marker below")
    },

    EngineCase("r77c-cross-line-still-plans") {
        // "7×8\n": the caret on line 1 (unit 4) referencing line 0 is the
        // canonical flow (Return, then double-click) and must still work.
        let content = "7×8\n"
        let (plan, lines) = r62Plan(content, sourceLineIndex: 0, caret: 4)
        guard case .number(let v, let u) = lines[0].result, u == nil, v == 56
        else { return try expect(false, "sanity: 7×8 answers 56") }
        guard let plan else {
            return try expect(false, "a cross-line caret on line 1 still plans the token")
        }
        try expectEqual(plan.content, content + WM,
                        "the marker lands at the line-1 caret, the source line is untouched")
        try expectEqual(plan.caret, 5, "the caret lands right after the marker")
        try expectEqual(plan.references.count, 1, "exactly one fresh reference")
        try expectEqual(plan.newReference.labelLine, 1, "the token keeps the 1-based source label")
    },

    EngineCase("r77c-caret-at-next-line-start-allowed") {
        // Unit 4 is the FIRST unit of line 1 (the line-0 range is the
        // half-open [0,4)) — a caret there belongs to line 1, not line 0,
        // so the plan is allowed (same as the cross-line case).
        let content = "7×8\n"
        let (plan, _) = r62Plan(content, sourceLineIndex: 0, caret: 4)
        try expect(plan != nil, "a caret at the next line's start is NOT on the source line")
    },
]
