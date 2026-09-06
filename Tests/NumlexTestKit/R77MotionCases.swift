import Foundation
import NumlexCore

/// r77b — Motion-policy unit cases: the injected-clock, state-based
/// appearance passes for answers and tokens. The answer trigger is the
/// RESULT, not the line's birth: quiet→result edges (blank or error →
/// a real answer) start one fade-in pass, result→result changes are
/// crossfade-only in the view, and seeded (pending) lines — initial
/// load, relaunch, sheet switch — adopt silently so already-visible
/// answers never replay. These exercise the exact state the app's
/// main-run-loop ticks drive, with no AppKit, timers or wall clock.
public let r77MotionCases: [EngineCase] = [
    EngineCase("r77b-seed-adopts-silently") {
        // Load: every line is seeded pending; the first observation
        // adopts the real result phases without a single pass, no
        // matter how many lines already show answers.
        var a = AnswerAppearance()
        let aID = UUID()
        let bID = UUID()
        a.seed(ids: [aID, bID])
        a.observe(entries: [
            AnswerMotionEntry(id: aID, key: "42"),
            AnswerMotionEntry(id: bID, key: nil),
        ], now: 10, reduceMotion: false)
        try expect(!a.isAnimating, "loaded answers never replay")
        // A later re-evaluation of the same state animates nothing.
        a.observe(entries: [
            AnswerMotionEntry(id: aID, key: "42"),
            AnswerMotionEntry(id: bID, key: nil),
        ], now: 11, reduceMotion: false)
        try expect(!a.isAnimating, "re-evaluation is quiet")
        try expect(a.progress(for: aID, now: 11.05) == nil, "final state")
    },

    EngineCase("r77b-empty-seeded-line-result-delayed") {
        // The user's actual case: an existing (seeded, previously
        // blank) line receives its FIRST answer much later than the
        // pass duration — the fade must start at the result edge,
        // not at line creation.
        var a = AnswerAppearance()
        let id = UUID()
        a.seed(ids: [id])
        a.observe(entries: [AnswerMotionEntry(id: id, key: nil)],
                  now: 0, reduceMotion: false)
        try expect(!a.isAnimating, "blank line: no pass")
        // The user types for half a second; the answer lands well
        // after any line-creation-based trigger could have fired.
        a.observe(entries: [AnswerMotionEntry(id: id, key: "42")],
                  now: 0.5, reduceMotion: false)
        try expect(a.isAnimating, "first result starts the pass")
        try expectClose(
            AnswerAppearance.opacity(progress: a.progress(for: id, now: 0.5)),
            0, 1e-9, "starts transparent at the result edge"
        )
        let mid = a.progress(for: id, now: 0.5 + AnswerAppearance.duration / 2)!
        try expect(mid > 0.5, "eased past half at the midpoint")
        try expect(
            a.progress(for: id, now: 0.5 + AnswerAppearance.duration + 0.01) == nil,
            "settles after the shared duration"
        )
        a.expire(now: 0.5 + AnswerAppearance.duration + 0.01)
        try expect(!a.isAnimating, "chain stopped")
    },

    EngineCase("r77b-new-blank-line-then-result") {
        // A genuinely new line (no seed — typed after load) starts as
        // noResult; its first result later starts the pass.
        var a = AnswerAppearance()
        let id = UUID()
        a.observe(entries: [AnswerMotionEntry(id: id, key: nil)],
                  now: 0, reduceMotion: false)
        try expect(!a.isAnimating, "new blank line: no pass yet")
        a.observe(entries: [AnswerMotionEntry(id: id, key: "7")],
                  now: 0.3, reduceMotion: false)
        try expect(a.isAnimating, "result on the new line starts the pass")
        try expectClose(
            AnswerAppearance.opacity(progress: a.progress(for: id, now: 0.3)),
            0, 1e-9, "transparent at the start"
        )
    },

    EngineCase("r77b-invalid-to-valid") {
        // An expression that is invalid (no result) becomes valid:
        // the quiet→result edge animates exactly like a blank line.
        var a = AnswerAppearance()
        let id = UUID()
        a.seed(ids: [id])
        a.observe(entries: [AnswerMotionEntry(id: id, key: nil)],
                  now: 0, reduceMotion: false)
        a.observe(entries: [AnswerMotionEntry(id: id, key: "12")],
                  now: 0.2, reduceMotion: false)
        try expect(a.isAnimating, "error→valid starts the pass")
        // Further value churn while answering is crossfade-only:
        a.observe(entries: [AnswerMotionEntry(id: id, key: "125")],
                  now: 0.25, reduceMotion: false)
        try expect(a.inFlight[id] != nil, "the pass is not restarted by value churn")
    },

    EngineCase("r77b-result-change-crossfade-only") {
        // A loaded, answering line whose VALUE changes (re-evaluation,
        // rounding, region) never starts an appearance pass — the view
        // crossfades the identity swap in place.
        var a = AnswerAppearance()
        let id = UUID()
        a.seed(ids: [id])
        a.observe(entries: [AnswerMotionEntry(id: id, key: "42")],
                  now: 0, reduceMotion: false)
        try expect(!a.isAnimating, "loaded answer adopted silently")
        a.observe(entries: [AnswerMotionEntry(id: id, key: "43")],
                  now: 1, reduceMotion: false)
        try expect(!a.isAnimating, "value change is crossfade-only, never a pass")
        a.observe(entries: [AnswerMotionEntry(id: id, key: "43")],
                  now: 2, reduceMotion: false)
        try expect(!a.isAnimating, "unchanged value is quiet")
    },

    EngineCase("r77b-new-result-line-unknown") {
        // A line that arrives already having a result (e.g. a line
        // created by a previous-answer token) fades in on sight.
        var a = AnswerAppearance()
        let id = UUID()
        a.observe(entries: [AnswerMotionEntry(id: id, key: "21")],
                  now: 0, reduceMotion: false)
        try expect(a.isAnimating, "new result line starts the pass")
    },

    EngineCase("r77b-result-cleared-reappears") {
        // Clearing a result returns the line to quiet (any in-flight
        // pass drops); a later result is a fresh quiet→result edge.
        var a = AnswerAppearance()
        let id = UUID()
        a.seed(ids: [id])
        a.observe(entries: [AnswerMotionEntry(id: id, key: "42")],
                  now: 0, reduceMotion: false)
        try expect(!a.isAnimating, "loaded answer adopted silently")
        a.observe(entries: [AnswerMotionEntry(id: id, key: nil)],
                  now: 0.1, reduceMotion: false)
        try expect(!a.isAnimating, "cleared result is quiet")
        a.observe(entries: [AnswerMotionEntry(id: id, key: "50")],
                  now: 1, reduceMotion: false)
        try expect(a.isAnimating, "reappearing result fades again")
        // A mid-pass clear drops the pass at once.
        a.observe(entries: [AnswerMotionEntry(id: id, key: nil)],
                  now: 1.05, reduceMotion: false)
        try expect(!a.isAnimating, "mid-pass clear drops the pass")
    },

    EngineCase("r77b-rapid-coalescing") {
        // Rapid editing: the quiet→result edge starts ONE pass; every
        // subsequent value change coalesces into the crossfade and
        // never restarts or extends the pass.
        var a = AnswerAppearance()
        let id = UUID()
        a.seed(ids: [id])
        a.observe(entries: [AnswerMotionEntry(id: id, key: nil)], now: 0, reduceMotion: false)
        a.observe(entries: [AnswerMotionEntry(id: id, key: "4")], now: 0.02, reduceMotion: false)
        let start = a.inFlight[id]!
        a.observe(entries: [AnswerMotionEntry(id: id, key: "42")], now: 0.06, reduceMotion: false)
        a.observe(entries: [AnswerMotionEntry(id: id, key: "424")], now: 0.1, reduceMotion: false)
        try expectClose(a.inFlight[id]!, start, 1e-9, "start time never moves")
        a.expire(now: start + AnswerAppearance.duration + 0.01)
        try expect(!a.isAnimating, "one pass, settled")
    },

    EngineCase("r77b-sheet-switch-reseed") {
        // Switching sheets seeds the new sheet's lines pending: its
        // already-visible answers are adopted silently (no replay),
        // and the old sheet's in-flight state is dropped.
        var a = AnswerAppearance()
        let oneID = UUID()
        let twoA = UUID()
        let twoB = UUID()
        a.observe(entries: [AnswerMotionEntry(id: oneID, key: nil)], now: 0, reduceMotion: false)
        a.observe(entries: [AnswerMotionEntry(id: oneID, key: "9")], now: 0.1, reduceMotion: false)
        try expect(a.isAnimating, "first sheet mid-pass")
        a.seed(ids: [twoA, twoB])
        a.observe(entries: [
            AnswerMotionEntry(id: twoA, key: "31"),
            AnswerMotionEntry(id: twoB, key: "7"),
        ], now: 1, reduceMotion: false)
        try expect(!a.isAnimating, "switched-to sheet's answers never replay")
        // Returning to the first sheet re-seeds it: no replay either.
        a.seed(ids: [oneID])
        a.observe(entries: [AnswerMotionEntry(id: oneID, key: "9")], now: 2, reduceMotion: false)
        try expect(!a.isAnimating, "returning sheet is adopted, not replayed")
    },

    EngineCase("r77b-reduce-motion-midflight") {
        var a = AnswerAppearance()
        let id = UUID()
        a.observe(entries: [AnswerMotionEntry(id: id, key: "42")],
                  now: 0, reduceMotion: false)
        try expect(a.isAnimating, "pass in flight")
        // The OS flips Reduce Motion mid-pass: everything settles now.
        a.observe(entries: [AnswerMotionEntry(id: id, key: "42")],
                  now: 0.05, reduceMotion: true)
        try expect(!a.isAnimating, "mid-flight pass cancelled")
        try expect(a.progress(for: id, now: 0.1) == nil, "final state immediately")
        // With Reduce Motion ON, result edges never schedule passes.
        let id2 = UUID()
        a.observe(entries: [AnswerMotionEntry(id: id2, key: nil)],
                  now: 1, reduceMotion: true)
        a.observe(entries: [AnswerMotionEntry(id: id2, key: "3")],
                  now: 1.1, reduceMotion: true)
        try expect(!a.isAnimating, "no pass under Reduce Motion")
    },

    EngineCase("r77b-removal-drops-pass") {
        var a = AnswerAppearance()
        let id = UUID()
        a.observe(entries: [AnswerMotionEntry(id: id, key: "42")],
                  now: 0, reduceMotion: false)
        try expect(a.isAnimating, "mid-pass")
        // The line is deleted: its ID leaves the entries.
        a.observe(entries: [], now: 0.05, reduceMotion: false)
        try expect(!a.isAnimating, "removal drops the pass")
        // A re-created line is a NEW identity: it animates fresh.
        let retyped = UUID()
        a.observe(entries: [AnswerMotionEntry(id: retyped, key: "42")],
                  now: 1, reduceMotion: false)
        try expect(a.isAnimating, "reinserted line animates")
    },

    EngineCase("r77b-duplicate-entries") {
        var a = AnswerAppearance()
        let id = UUID()
        a.observe(entries: [
            AnswerMotionEntry(id: id, key: "42"),
            AnswerMotionEntry(id: id, key: "42"),
            AnswerMotionEntry(id: id, key: "42"),
        ], now: 0, reduceMotion: false)
        try expect(a.inFlight.count == 1, "duplicate entries collapse to one pass")
        a.expire(now: AnswerAppearance.duration + 0.01)
        a.observe(entries: [AnswerMotionEntry(id: id, key: "42"),
                           AnswerMotionEntry(id: id, key: "42")],
                  now: 1, reduceMotion: false)
        try expect(!a.isAnimating, "duplicates never replay")
    },

    EngineCase("r77b-answer-opacity-curve") {
        // Opacity-only: the value is monotone 0 → 1 and the settled
        // value is exactly the final text state. The eased curve is
        // baked into `progress()`; `opacity` maps it 1:1 so the view
        // can never introduce a second, layout-affecting tween.
        let p0 = AnswerAppearance.opacity(progress: 0)
        let pLow = AnswerAppearance.opacity(progress: 0.3)
        let pHigh = AnswerAppearance.opacity(progress: 0.7)
        let p1 = AnswerAppearance.opacity(progress: 1)
        try expectClose(p0, 0, 1e-9, "starts transparent")
        try expectClose(p1, 1, 1e-9, "ends fully opaque")
        try expect(pLow > p0 && pHigh > pLow && p1 > pHigh, "monotone ramp")
        try expect(AnswerAppearance.opacity(progress: nil) == 1, "settled = final")
        try expect(
            AnswerAppearance.ease(0.5) > 0.5,
            "the baked-in curve eases out (fast start, settled end)"
        )
        try expect(
            AnswerAppearance.ease(1) == 1,
            "the curve ends exactly settled"
        )
    },

    EngineCase("r77-token-restrained-settle") {
        // The token bubble settle is restrained (0.94 → 1); the label
        // is never scaled and the pass eases and settles.
        try expectClose(
            TokenAppearance.startScale, 0.94, 1e-9, "restrained start scale"
        )
        try expectClose(
            TokenAppearance.scale(progress: 0), TokenAppearance.startScale, 1e-9, "start"
        )
        try expectClose(TokenAppearance.scale(progress: 1), 1, 1e-9, "end")
        try expectClose(TokenAppearance.scale(progress: nil), 1, 1e-9, "final = settled")
        let mid = TokenAppearance.scale(progress: 0.5)
        try expect(
            mid > TokenAppearance.startScale && mid < 1, "monotone settle"
        )
    },

    EngineCase("r77-token-cancel-all") {
        var a = TokenAppearance()
        let id = UUID()
        a.observe(ids: [id], now: 0, reduceMotion: false)
        try expect(a.isAnimating, "pass in flight")
        a.cancelAll()
        try expect(!a.isAnimating, "Reduce Motion mid-flight settles")
        try expect(a.progress(for: id, now: 0.1) == nil, "final state")
        try expectClose(
            TokenAppearance.scale(progress: a.progress(for: id, now: 0.1)),
            1, 1e-9, "draws final geometry"
        )
    },
]
