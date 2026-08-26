import Foundation
import NumlexCore

// MARK: - r18: prose money, token+money mixing, natural autospacing, token appearance

private let M = "\u{FFFC}"

private func r18Rates() -> Rates {
    Rates(base: "USD", rates: ["USD": 1, "EUR": 1.1, "RUB": 90, "JPY": 150])
}

private func e18(_ line: String) -> LineResult? {
    var v = [String: Double]()
    return evalLine(line, variables: &v, rates: r18Rates(), decimalPlaces: 7)
}

private func isMoney(_ r: LineResult?, code: String? = nil) -> Bool {
    if case .some(.money) = r { return true }
    if case .some(.number(_, let u)) = r {
        return code == nil
            || (u != nil && isCurrencyCode(u) && u!.uppercased() == code)
    }
    return false
}

private func moneyValue(_ r: LineResult?) -> Double? {
    guard let r else { return nil }
    switch r {
    case .money(let v, _): return v
    case .number(let v, let u) where isCurrencyCode(u): return v
    default: return nil
    }
}

private func isError(_ r: LineResult?) -> Bool {
    if case .some(.error) = r { return true }
    return false
}

/// Resolves `src` (line 1) + `tail` (line 2, holding the marker(s));
/// one reference per marker in order, at the given source line IDs.
private func twoLine(src: String, tail: String,
                     ids: [UUID], sources: [UUID],
                     rates: Rates = r18Rates()) -> ([SheetLine], [TokenResolution]) {
    let content = src + "\n" + tail
    var refs: [AnswerReference] = []
    var scan = 0
    let ns = tail as NSString
    for source in sources {
        let r = ns.range(of: M, range: NSRange(location: scan, length: ns.length - scan))
        if r.location == NSNotFound { break }
        refs.append(AnswerReference(
            sourceLineID: source,
            labelLine: 1,
            location: (src as NSString).length + 1 + r.location))
        scan = r.location + 1
    }
    return resolveSheet(content: content, lineIDs: ids, references: refs,
                        rates: rates, decimalPlaces: 7)
}

public let r18Cases: [EngineCase] = [
    // MARK: Task 1 — prose money (no `=`, neutral labels)

    EngineCase("r18-food-star") {
        let r = e18("food $50 per day * 30 days")
        try expect(isMoney(r), "no-equals food line with ASCII * is money: \(r)")
        try expectClose(moneyValue(r)!, 1500, 1e-9, "USD 1500")
    },

    EngineCase("r18-food-times") {
        let r = e18("food $50 per day × 30 days")
        try expect(isMoney(r), "canonical × form: \(r)")
        try expectClose(moneyValue(r)!, 1500, 1e-9, "USD 1500")
    },

    EngineCase("r18-materials-literal") {
        let r = e18("$680.00 + materials $240")
        try expect(isMoney(r), "literal materials line: \(r)")
        try expectClose(moneyValue(r)!, 920, 1e-9, "USD 920")
    },

    EngineCase("r18-food-materials-mixed-currency") {
        let r = e18("$10 + food €5")
        try expect(isError(r), "mixed currencies hide an error: \(r)")
    },

    EngineCase("r18-materials-prose-stays-prose") {
        let r = e18("materials for the fence")
        try expect(!isMoney(r) && !isError(r),
                   "no money context: prose stays prose: \(r)")
    },

    // MARK: Task 2 — tokens mixed with literal money

    EngineCase("r18-token-plus-materials") {
        let u0 = UUID()
        let (lines, _) = twoLine(src: "$680.00", tail: M + " + materials $240",
                                 ids: [u0, UUID()], sources: [u0])
        let r = lines[1].result
        try expect(isMoney(r, code: "USD"), "token + materials: \(r)")
        try expectClose(moneyValue(r)!, 920, 1e-9, "USD 920")
    },

    EngineCase("r18-materials-plus-token") {
        let u0 = UUID()
        let (lines, _) = twoLine(src: "$680.00", tail: "materials $240 + " + M,
                                 ids: [u0, UUID()], sources: [u0])
        let r = lines[1].result
        try expect(isMoney(r, code: "USD"), "materials + token (prose first): \(r)")
        try expectClose(moneyValue(r)!, 920, 1e-9, "USD 920")
    },

    EngineCase("r18-token-postfix-literal") {
        let u0 = UUID()
        let (lines, _) = twoLine(src: "$680.00", tail: M + " + 240$",
                                 ids: [u0, UUID()], sources: [u0])
        let r = lines[1].result
        try expect(isMoney(r, code: "USD"), "token + postfix literal: \(r)")
        try expectClose(moneyValue(r)!, 920, 1e-9, "USD 920")
    },

    EngineCase("r18-token-grouped-literal") {
        let u0 = UUID()
        let (lines, _) = twoLine(src: "$680.00", tail: M + " + $1,200.50",
                                 ids: [u0, UUID()], sources: [u0])
        let r = lines[1].result
        try expect(isMoney(r, code: "USD"), "grouped literal: \(r)")
        try expectClose(moneyValue(r)!, 1880.5, 1e-9, "USD 1,880.50")
    },

    EngineCase("r18-token-compact-suffix") {
        let u0 = UUID()
        let (lines, _) = twoLine(src: "$2.5k", tail: M + " + 500$",
                                 ids: [u0, UUID()], sources: [u0])
        let r = lines[1].result
        try expect(isMoney(r, code: "USD"), "compact suffix source: \(r)")
        try expectClose(moneyValue(r)!, 3000, 1e-9, "USD 3,000")
    },

    EngineCase("r18-token-contextual-percent") {
        let u0 = UUID()
        let (lines, _) = twoLine(src: "$680.00", tail: M + " + 10%",
                                 ids: [u0, UUID()], sources: [u0])
        let r = lines[1].result
        try expect(isMoney(r, code: "USD"), "contextual percent on money token: \(r)")
        try expectClose(moneyValue(r)!, 748, 1e-9, "USD 748")
    },

    EngineCase("r18-token-scalar-multiply") {
        let u0 = UUID()
        let (lines, _) = twoLine(src: "$680.00", tail: M + " × 2",
                                 ids: [u0, UUID()], sources: [u0])
        let r = lines[1].result
        try expect(isMoney(r, code: "USD"), "scalar multiply keeps currency: \(r)")
        try expectClose(moneyValue(r)!, 1360, 1e-9, "USD 1,360")
    },

    EngineCase("r18-token-mixed-currency-error") {
        let u0 = UUID()
        let (lines, _) = twoLine(src: "$680.00", tail: M + " + €5",
                                 ids: [u0, UUID()], sources: [u0])
        let r = lines[1].result
        try expect(isError(r), "different currencies error: \(r)")
    },

    EngineCase("r18-measurement-token-plus-money-error") {
        let u0 = UUID()
        let (lines, _) = twoLine(src: "100 m", tail: M + " + $5",
                                 ids: [u0, UUID()], sources: [u0])
        let r = lines[1].result
        try expect(isError(r), "measurement token + money errors: \(r)")
    },

    EngineCase("r18-prose-before-token-range-stable") {
        // A neutral word BEFORE the marker must not shift the marker's
        // offset (the mask is range-preserving): the token stays active.
        let u0 = UUID()
        let (lines, tokens) = twoLine(src: "$680.00", tail: "materials " + M,
                                      ids: [u0, UUID()], sources: [u0])
        let r = lines[1].result
        try expect(isMoney(r, code: "USD"), "prose before bare token: \(r)")
        try expectClose(moneyValue(r)!, 680, 1e-9, "USD 680")
        try expect(tokens.count == 1, "one token state")
        if case .active(let v, _, _)? = tokens.first?.state {
            try expectClose(v, 680, 1e-9, "token stays active")
        } else {
            try expect(false, "token must resolve, got \(tokens)")
        }
    },

    EngineCase("r18-two-tokens") {
        let u0 = UUID(), u1 = UUID()
        let content = "$680.00\n$240\n" + M + " + " + M
        let refs = [
            AnswerReference(sourceLineID: u0, labelLine: 1, location: 13),
            AnswerReference(sourceLineID: u1, labelLine: 2, location: 17),
        ]
        let (lines, tokens) = resolveSheet(content: content, lineIDs: [u0, u1, UUID()],
                                           references: refs, rates: r18Rates(),
                                           decimalPlaces: 7)
        let r = lines[2].result
        try expect(isMoney(r, code: "USD"), "two tokens add: \(r)")
        try expectClose(moneyValue(r)!, 920, 1e-9, "USD 920")
        try expect(tokens.count == 2, "two token states")
    },

    EngineCase("r18-broken-token-in-money-line") {
        let u0 = UUID()
        let content = "no number here\n" + M + " + materials $240"
        let refs = [AnswerReference(sourceLineID: u0, labelLine: 1,
                                    location: 15)]
        let (lines, _) = resolveSheet(content: content, lineIDs: [u0, UUID()],
                                      references: refs, rates: r18Rates(),
                                      decimalPlaces: 7)
        let r = lines[1].result
        try expect(isError(r), "broken token in money line hides error: \(r)")
    },
]

// MARK: - Task 3 — natural operator canonicalization (formatting layer)

public let r18FormatCases: [EngineCase] = [
    EngineCase("r18-format-food-star") {
        try expectEqual(NotebookFormatting.canonicalDocument("food $50 per day*30 days"),
                        "food $50 per day × 30 days",
                        "ASCII * canonicalizes to ×")
    },

    EngineCase("r18-format-materials-plus") {
        try expectEqual(NotebookFormatting.canonicalDocument("$680.00+materials $240"),
                        "$680.00 + materials $240",
                        "exactly one space around +")
    },

    EngineCase("r18-format-contractor-rate") {
        try expectEqual(NotebookFormatting.canonicalDocument("contractor $85/hr*8 hrs"),
                        "contractor $85 / hr × 8 hrs",
                        "rate spacing")
    },

    EngineCase("r18-format-token-line") {
        let canon = NotebookFormatting.canonicalDocument(M + "+$240")
        try expectEqual(canon, M + " + $240", "token line operator spacing")
        try expect(canon.hasPrefix(M), "marker identity survives")
    },

    EngineCase("r18-format-env-advances") {
        // `rent × 12` only normalizes once the typed env knows `rent`.
        try expectEqual(NotebookFormatting.canonicalDocument("rent = $5\nrent×12"),
                        "rent = $5\nrent × 12",
                        "natural branch advances the env")
    },

    EngineCase("r18-format-no-double-space") {
        try expectEqual(NotebookFormatting.canonicalDocument("1+ 2"),
                        "1 + 2", "double space collapses")
        try expectEqual(NotebookFormatting.canonicalDocument("1+2"),
                        "1 + 2", "no spaces expands")
        try expectEqual(NotebookFormatting.canonicalDocument("1+ 2 +3"),
                        "1 + 2 + 3", "both sides normalized")
    },

    EngineCase("r18-format-unary-and-prose-untouched") {
        try expectEqual(NotebookFormatting.canonicalDocument("-5 + 3"),
                        "-5 + 3", "unary minus not re-spaced")
        try expectEqual(NotebookFormatting.canonicalDocument("state-of-the-art and/or fence"),
                        "state-of-the-art and/or fence", "prose untouched")
        try expectEqual(NotebookFormatting.canonicalDocument("food  $50  per day"),
                        "food  $50  per day", "interior prose spaces preserved")
    },

    EngineCase("r18-format-caret-map-monotone") {
        let pairs: [(String, String)] = [
            ("food $50 per day*30 days", "food $50 per day × 30 days"),
            (M + "+$240", M + " + $240"),
            ("$680.00+materials $240", "$680.00 + materials $240"),
            ("1+2", "1 + 2"),
        ]
        for (from, to) in pairs {
            let map = NotebookFormatting.mapDocument(from: from, to: to)
            try expect(map.count == (from.utf16.count) + 1,
                       "map has one entry per caret position: \(from) -> \(to)")
            var prev = 0
            for p in 0...(from.utf16.count) {
                let v = map[p] ?? 0
                try expect(v >= prev, "map monotone at \(p): \(from) -> \(to)")
                prev = v
            }
            // Idempotence: canonicalizing the result again is a no-op.
            try expectEqual(NotebookFormatting.canonicalDocument(to), to,
                            "fixed point: \(to)")
        }
    },

    EngineCase("r18-format-every-prefix-fixed-point") {
        let full = "food $50 per day*30 days"
        var prefix = ""
        for ch in full {
            prefix.append(ch)
            let canon = NotebookFormatting.canonicalDocument(prefix)
            let map = NotebookFormatting.mapDocument(from: prefix, to: canon)
            // Caret monotone on EVERY mid-typing prefix.
            var prev = 0
            for p in 0...prefix.utf16.count {
                let v = map[p] ?? 0
                try expect(v >= prev, "prefix monotone at \(p): '\(prefix)' -> '\(canon)'")
                prev = v
            }
            try expectEqual(NotebookFormatting.canonicalDocument(canon), canon,
                            "prefix fixed point: '\(prefix)'")
        }
    },

    EngineCase("r18-reference-survives-operator-spacing") {
        // Token alone on its line; the user types `+240$` right after it,
        // then the canonical pass re-spaces. The reference ID and marker
        // location must stay exact.
        let u0 = UUID(), u1 = UUID()
        let ref = AnswerReference(sourceLineID: u0, labelLine: 1, location: 0)
        let old = M
        let edit = NotebookEdit(range: NSRange(location: 1, length: 0),
                                replacement: "+240$")
        let new = (old as NSString).replacingCharacters(in: edit.range!, with: edit.replacement)
        let r = LineIdentity.reconcile(oldContent: old, oldLineIDs: [u0, u1],
                                       oldReferences: [ref], newContent: new, edit: edit)
        try expect(r.references.count == 1, "reference survives the edit")
        try expectEqual(r.references.first?.location, 0, "marker still at 0")
        let canon = NotebookFormatting.canonicalDocument(new)
        try expectEqual(canon, M + " + 240$", "canonical form")
        let map = NotebookFormatting.mapDocument(from: new, to: canon)
        let p = map[r.references[0].location] ?? -1
        try expectEqual(p, 0, "marker maps to 0 after canonical spacing")
        try expect((canon as NSString).character(at: p) == answerTokenMarkerUTF16,
                   "U+FFFC at mapped location")
    },
]

// MARK: - Task 4 — token appearance state diff (pure, clock-injected)

public let r18AnimationCases: [EngineCase] = [
    EngineCase("r18-anim-seed-never-replays") {
        var a = TokenAppearance()
        let id = UUID()
        a.seed(ids: [id])
        let fresh = a.observe(ids: [id], now: 100, reduceMotion: false)
        try expect(fresh.isEmpty, "seeded IDs are never 'new'")
        try expect(!a.isAnimating, "no pass scheduled")
    },

    EngineCase("r18-anim-new-id-plays-once") {
        var a = TokenAppearance()
        let aID = UUID(), bID = UUID()
        a.seed(ids: [aID])
        let fresh = a.observe(ids: [aID, bID], now: 100, reduceMotion: false)
        try expectEqual(fresh, [bID], "exactly the new ID")
        try expect(a.isAnimating, "pass in flight")
        // Mid-pass progress exists and eases toward 1.
        let p1 = a.progress(for: bID, now: 100.05)
        let p2 = a.progress(for: bID, now: 100.10)
        try expect(p1 != nil, "progress mid-pass")
        try expect(p2 != nil && p2! > p1!, "progress increasing")
        // After the duration the pass is gone (final state).
        try expect(a.progress(for: bID, now: 100.3) == nil, "settled after duration")
        a.expire(now: 100.3)
        try expect(!a.isAnimating, "chain stops")
        // Observing the same ID again (e.g. a live update) does not
        // replay: it is known now.
        let fresh2 = a.observe(ids: [aID, bID], now: 101, reduceMotion: false)
        try expect(fresh2.isEmpty, "no replay for known IDs")
    },

    EngineCase("r18-anim-live-update-no-replay") {
        // Label/source updates and broken/recovered transitions keep the
        // ID set: nothing may animate.
        var a = TokenAppearance()
        let id = UUID()
        a.seed(ids: [id])
        a.observe(ids: [id], now: 50, reduceMotion: false)
        let fresh = a.observe(ids: [id], now: 51, reduceMotion: false)
        try expect(fresh.isEmpty, "ID set unchanged → no pass")
        try expect(!a.isAnimating, "still settled")
    },

    EngineCase("r18-anim-removal-drops-pass") {
        var a = TokenAppearance()
        let aID = UUID(), bID = UUID()
        a.seed(ids: [aID])
        a.observe(ids: [aID, bID], now: 10, reduceMotion: false)
        try expect(a.isAnimating, "b animating")
        // b is deleted mid-pass.
        a.observe(ids: [aID], now: 10.05, reduceMotion: false)
        try expect(!a.isAnimating, "removed token stops ticking")
        try expect(a.progress(for: bID, now: 10.1) == nil, "b has no pass")
    },

    EngineCase("r18-anim-reduce-motion-jumps-to-final") {
        var a = TokenAppearance()
        let id = UUID()
        let fresh = a.observe(ids: [id], now: 1, reduceMotion: true)
        try expectEqual(fresh, [id], "still reported as introduced")
        try expect(!a.isAnimating, "no pass under Reduce Motion")
        try expect(a.progress(for: id, now: 1.05) == nil,
                   "final state immediately (progress nil)")
    },

    EngineCase("r18-anim-ease-and-scale") {
        try expectEqual(TokenAppearance.ease(0), 0, "ease(0)")
        try expectEqual(TokenAppearance.ease(1), 1, "ease(1)")
        let t: [Double] = [0.0, 0.05, 0.1, 0.15, 0.19, 1.0]
        var prev = 0.0
        for x in t {
            let e = TokenAppearance.ease(x)
            try expect(e >= prev, "ease monotone at \(x)")
            prev = e
        }
        try expectEqual(TokenAppearance.scale(progress: nil), 1, "final scale")
        try expectClose(TokenAppearance.scale(progress: 0), 0.84, 1e-9, "start scale")
        try expectEqual(TokenAppearance.scale(progress: 1), 1, "end scale")
        try expectEqual(TokenAppearance.opacity(progress: nil), 1, "final opacity")
        try expectEqual(TokenAppearance.opacity(progress: 0), 0, "start opacity")
    },
]
