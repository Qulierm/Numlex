import Foundation

/// One line's reported motion-relevant state (r77b). The app feeds the
/// appearance state, after EVERY re-evaluation, one entry per source
/// line: the line's STABLE UUID and its result phase. `key` is the
/// displayed answer string — the very string the answer view uses as
/// its crossfade identity (so a changed value crossfades, never
/// re-inserts) — or nil when the line shows no real answer (blank,
/// heading, error, quiet status, broken token).
public struct AnswerMotionEntry: Equatable, Sendable {
    public let id: UUID
    public let key: String?

    public init(id: UUID, key: String?) {
        self.id = id
        self.key = key
    }
}

/// Pure, clock-injected answer-appearance state (r77b). The trigger is
/// the RESULT, not the line's birth: a line that goes from quiet
/// (no result: blank, error, hidden) to a real answer plays ONE
/// fade-in pass, whether that line is brand new or has sat empty for
/// an hour. A result that CHANGES on an already-answering line is not
/// a pass — the view crossfades the value in place (identity swap,
/// 0.12 s). Loaded sheets and sheet switches are seeded `pending`:
/// their first observation adopts the actual phases silently, so
/// relaunch, sheet switch, theme/locale/region/style changes and any
/// other full re-evaluation never replay insertions. Rapid edits
/// coalesce naturally: only the quiet→result edge starts a pass, and
/// value churn afterwards is crossfade-only. Disappeared lines drop
/// their pass. All time is caller-supplied (seconds) so the logic is
/// deterministic and unit-testable without AppKit, timers or the main
/// thread.
public struct AnswerAppearance: Equatable {
    /// The appearance-pass duration (seconds): a visible, restrained
    /// fade-in for an answer that just appeared (180–220 ms band).
    public static let duration: TimeInterval = 0.18

    public enum Phase: Equatable, Sendable {
        /// Seeded (load / relaunch / sheet switch) but not yet
        /// observed: the next observation adopts the real phase
        /// WITHOUT a pass.
        case pending
        /// The line currently shows no real answer.
        case noResult
        /// The line shows an answer, identified by its display key.
        case result(key: String)
    }

    private var known: [UUID: Phase]
    /// Line ID → start time (seconds) of its in-flight fade-in.
    public private(set) var inFlight: [UUID: TimeInterval]

    public init() {
        known = [:]
        inFlight = [:]
    }

    /// Registers the lines present at load/relaunch or sheet switch.
    /// They become `pending`: the first observation adopts their real
    /// phases silently (no replay of already-visible answers).
    public mutating func seed(ids: [UUID]) {
        for id in ids { known[id] = .pending }
    }

    /// Observes the current per-line result state at `now`.
    /// - A `pending` or never-seen line adopts its phase; a never-seen
    ///   line that ALREADY has a result (a freshly created result
    ///   line) starts a pass.
    /// - A `noResult` line that gains a result starts ONE pass.
    /// - A `result` line whose key changes updates the key without a
    ///   pass (the view crossfades); a line that loses its result
    ///   returns to `noResult` silently.
    /// - IDs no longer present drop their pass and phase.
    /// Duplicate IDs inside one call collapse to the first entry.
    /// When `reduceMotion` is true no pass is scheduled and any pass
    /// already in flight is cancelled (the caller renders the final
    /// state).
    @discardableResult
    public mutating func observe(
        entries: [AnswerMotionEntry],
        now: TimeInterval,
        reduceMotion: Bool
    ) -> [UUID] {
        var fresh: [UUID] = []
        if reduceMotion {
            // Reduce Motion flipped on mid-pass: everything settles now.
            inFlight.removeAll()
        }
        var seen = Set<UUID>()
        for entry in entries {
            guard !seen.contains(entry.id) else { continue }
            seen.insert(entry.id)
            let phase: Phase = entry.key.map { .result(key: $0) } ?? .noResult
            switch known[entry.id] {
            case .some(.pending):
                // Load / sheet switch adoption: silent.
                known[entry.id] = phase
            case .some(.noResult):
                known[entry.id] = phase
                if case .result = phase, !reduceMotion {
                    inFlight[entry.id] = now
                    fresh.append(entry.id)
                }
            case .some(.result(let oldKey)):
                known[entry.id] = phase
                if case .result = phase {
                    // Value changed (or identical): the view
                    // crossfades; no insertion pass.
                } else {
                    // Result cleared: the row goes quiet immediately.
                    inFlight.removeValue(forKey: entry.id)
                }
            case .none:
                known[entry.id] = phase
                if case .result = phase, !reduceMotion {
                    inFlight[entry.id] = now
                    fresh.append(entry.id)
                }
            }
        }
        // Removal: lines that left the sheet drop phase and pass.
        for id in known.keys where !seen.contains(id) {
            known.removeValue(forKey: id)
            inFlight.removeValue(forKey: id)
        }
        return fresh
    }

    /// The eased progress (0...1) of the pass for one ID at `now`, or
    /// nil when the ID is not mid-pass (render the final state).
    public func progress(for id: UUID, now: TimeInterval) -> Double? {
        guard let start = inFlight[id] else { return nil }
        let t = (now - start) / Self.duration
        if t < 0 { return 0 }
        if t >= 1 { return nil }
        return Self.ease(min(t, 1))
    }

    /// Drops finished passes. Call once per tick frame.
    public mutating func expire(now: TimeInterval) {
        inFlight = inFlight.filter { now - $0.value < Self.duration }
    }

    /// Whether any pass is still in flight (the tick timer should run).
    public var isAnimating: Bool {
        !inFlight.isEmpty
    }

    /// Cancels every in-flight pass (Reduce Motion flipped on mid-pass):
    /// the caller renders the final state and stops ticking.
    public mutating func cancelAll() {
        inFlight.removeAll()
    }

    /// Drawn opacity for a progress value (nil progress = final).
    public static func opacity(progress: Double?) -> Double {
        progress ?? 1
    }

    /// Short eased/snappy curve: fast out, settled end — the same
    /// character as the token pass, so both surfaces breathe together.
    public static func ease(_ t: Double) -> Double {
        let c = 1 - min(max(t, 0), 1)
        return 1 - c * c * c
    }
}
