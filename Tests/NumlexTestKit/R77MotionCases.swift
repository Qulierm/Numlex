import Foundation
import NumlexCore

/// r77 — Motion-policy unit cases: the injected-clock, state-based
/// appearance passes for answers and tokens. These exercise the exact
/// same state the app's main-run-loop ticks drive, with no AppKit and
/// no wall clock: seed suppression, one-shot passes, deletion/reinsert-
/// ion, duplicate IDs, relabel coalescing, Reduce Motion mid-flight
/// cancellation and cancelAll. The AppKit/SwiftUI wiring (row opacity,
/// identity crossfade, capsule ring) is validated visually in the real
/// app, never by these state machines.
public let r77MotionCases: [EngineCase] = [
    EngineCase("r77-answer-seed-suppresses-load") {
        var a = AnswerAppearance()
        let aID = UUID()
        let bID = UUID()
        a.seed(ids: [aID, bID])
        let fresh = a.observe(ids: [aID, bID], now: 10, reduceMotion: false)
        try expect(fresh.isEmpty, "loaded lines never animate")
        try expect(!a.isAnimating, "no pass scheduled on load")
        try expect(a.progress(for: aID, now: 10.05) == nil, "final state")
    },

    EngineCase("r77-answer-new-line-animates-once") {
        var a = AnswerAppearance()
        a.seed(ids: [])
        let id = UUID()
        let fresh = a.observe(ids: [id], now: 0, reduceMotion: false)
        try expectEqual(fresh, [id], "new line reported once")
        try expectClose(
            AnswerAppearance.opacity(progress: a.progress(for: id, now: 0)),
            0, 1e-9, "starts transparent"
        )
        // The pass eases (past half by the midpoint, unlike linear).
        let p = a.progress(for: id, now: AnswerAppearance.duration / 2)!
        try expect(p > 0.5, "eased past half at midpoint")
        try expect(
            a.progress(for: id, now: AnswerAppearance.duration + 0.01) == nil,
            "settles after the shared 180 ms duration"
        )
        a.expire(now: AnswerAppearance.duration + 0.01)
        // Re-observing the same ID set never replays the pass.
        let again = a.observe(ids: [id], now: 100, reduceMotion: false)
        try expect(again.isEmpty, "known line is not re-animated")
        try expect(!a.isAnimating, "chain is stopped")
    },

    EngineCase("r77-answer-removal-and-reinsertion") {
        var a = AnswerAppearance()
        let id = UUID()
        let fresh = UUID()
        a.seed(ids: [id])
        a.observe(ids: [id, fresh], now: 10, reduceMotion: false)
        try expect(a.isAnimating, "fresh line mid-pass")
        // Deleting the line mid-pass stops the pass (the tick reads
        // the latest sheet state every frame).
        a.observe(ids: [id], now: 10.05, reduceMotion: false)
        try expect(!a.isAnimating, "removal stops the in-flight pass")
        try expect(a.progress(for: fresh, now: 10.1) == nil, "no pass after removal")
        // Re-typing the line arrives as a NEW UUID and animates once.
        let retyped = UUID()
        let freshIDs = a.observe(ids: [id, retyped], now: 20, reduceMotion: false)
        try expectEqual(freshIDs, [retyped], "reinsertion animates")
        try expectClose(
            AnswerAppearance.opacity(progress: a.progress(for: retyped, now: 20)),
            0, 1e-9, "starts transparent"
        )
    },

    EngineCase("r77-answer-repeated-ids") {
        var a = AnswerAppearance()
        let id = UUID()
        let fresh = a.observe(ids: [id, id, id], now: 1, reduceMotion: false)
        try expectEqual(fresh, [id], "duplicates collapse to one fresh pass")
        try expect(a.inFlight.count == 1, "one in-flight entry")
        a.expire(now: 2)
        a.observe(ids: [id, id], now: 2, reduceMotion: false)
        try expect(!a.isAnimating, "re-observing duplicates never replays")
    },

    EngineCase("r77-answer-relabel-never-replays") {
        var a = AnswerAppearance()
        let id = UUID()
        a.seed(ids: [id])
        a.observe(ids: [id], now: 1, reduceMotion: false)
        // Relabel / re-evaluation keeps the ID set unchanged: no pass,
        // ever — the displayed value changes in place instead.
        let fresh = a.observe(ids: [id], now: 2, reduceMotion: false)
        try expect(fresh.isEmpty, "ID set unchanged → no appearance pass")
        try expect(!a.isAnimating, "settled")
    },

    EngineCase("r77-answer-coalescing") {
        var a = AnswerAppearance()
        // Rapid successive insertions (fast typing): each new line
        // gets its own start time; the single shared tick coalesces to
        // the LATEST state, so all passes stay in lockstep with the
        // wall clock.
        let aID = UUID()
        let bID = UUID()
        let cID = UUID()
        a.observe(ids: [aID], now: 0, reduceMotion: false)
        a.observe(ids: [aID, bID], now: 0.05, reduceMotion: false)
        a.observe(ids: [aID, bID, cID], now: 0.1, reduceMotion: false)
        try expect(a.isAnimating, "all three lines mid-pass")
        let now = 0.1 + AnswerAppearance.duration / 2
        // aID's pass (started at 0) has already SETTLED at this point
        // (duration 0.18 < 0.19) and reads as nil = final state.
        try expect(a.progress(for: aID, now: now) == nil, "oldest pass settled to final")
        let pb = a.progress(for: bID, now: now)!
        let pc = a.progress(for: cID, now: now)!
        try expect(pb > pc, "older pass is further along than the newest")
        a.expire(now: now)
        try expect(a.inFlight[cID] != nil, "newest pass still in flight")
        a.expire(now: 0.1 + AnswerAppearance.duration + 0.01)
        try expect(!a.isAnimating, "chain stops only after the LAST pass")
        try expect(a.inFlight.isEmpty, "no residual state")
    },

    EngineCase("r77-answer-reducemotion-midflight") {
        var a = AnswerAppearance()
        let id = UUID()
        a.observe(ids: [id], now: 0, reduceMotion: false)
        try expect(a.isAnimating, "pass in flight")
        // The OS flips Reduce Motion mid-pass: everything settles now
        // and the app's tick stops the chain from the next frame.
        a.observe(ids: [id], now: 0.05, reduceMotion: true)
        try expect(!a.isAnimating, "mid-flight pass cancelled")
        try expect(a.progress(for: id, now: 0.1) == nil, "final state immediately")
        // New lines while Reduce Motion is ON never schedule a pass.
        let id2 = UUID()
        let fresh = a.observe(ids: [id, id2], now: 1, reduceMotion: true)
        try expectEqual(fresh, [id2], "still tracked for future playback")
        try expect(!a.isAnimating, "no pass under Reduce Motion")
    },

    EngineCase("r77-answer-cancel-all") {
        var a = AnswerAppearance()
        let id = UUID()
        a.observe(ids: [id], now: 0, reduceMotion: false)
        try expect(a.isAnimating, "pass in flight")
        a.cancelAll()
        try expect(!a.isAnimating, "cancelAll stops the chain")
        try expect(a.inFlight.isEmpty, "state cleared")
        try expect(a.progress(for: id, now: 1) == nil, "final state")
    },

    EngineCase("r77-answer-opacity-curve") {
        // Opacity-only: the value is monotone 0 → 1 and the settled
        // value is exactly the final text state. The eased curve lives
        // in `progress()` (already eased); `opacity` maps it 1:1 so the
        // view can never introduce a second, layout-affecting tween.
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
        // r77: the ink settle is restrained (0.94 → 1); the label is
        // never scaled and the pass still eases and settles.
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
        try expectClose(TokenAppearance.scale(progress: a.progress(for: id, now: 0.1)), 1, 1e-9, "draws final geometry")
    },
]
