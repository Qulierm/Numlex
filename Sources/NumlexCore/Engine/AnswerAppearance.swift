import Foundation

/// Pure, clock-injected appearance-animation state for NEW answer rows
/// (r77). The app model feeds it the selected sheet's STABLE line UUIDs
/// on every evaluation; the line IDs present at `seed` (initial load,
/// relaunch, sheet switch) never animate, and only IDs that are NEWLY
/// introduced (a line the user newly typed, a line re-created after a
/// deletion) get ONE fade-in pass. Live re-evaluations, caret moves,
/// highlighting and view re-renders change neither the ID set nor any
/// start time, so they never replay. Changed displayed values on an
/// EXISTING line are not this struct's concern — the view crossfades
/// those directly (content transition, no row-frame movement).
///
/// All time is caller-supplied (seconds), so the logic is deterministic
/// and unit-testable without AppKit, timers or the main thread.
public struct AnswerAppearance: Equatable {
    /// The appearance pass duration (seconds): a restrained fade-in for
    /// a freshly computed answer.
    public static let duration: TimeInterval = 0.18

    /// Line IDs already present when this app instance first saw the
    /// sheet (or before) — these never animate in this instance.
    private var known: Set<UUID>
    /// Line ID → start time (seconds) of its one in-flight fade-in.
    public private(set) var inFlight: [UUID: TimeInterval]

    public init() {
        known = []
        inFlight = [:]
    }

    /// Registers the line IDs already on the sheet when this instance
    /// attaches (load / relaunch) or when the user switches sheets.
    /// They become known WITHOUT animating.
    public mutating func seed(ids: [UUID]) {
        known.formUnion(ids)
    }

    /// Observes the current ID set at `now`. Returns the IDs that are
    /// NEWLY introduced (in order of first appearance) — those are the
    /// ones that should play exactly one fade-in. When `reduceMotion`
    /// is true no pass is scheduled at all (and any pass already
    /// in flight is cancelled, so a mid-flight switch to Reduce Motion
    /// settles instantly), and the caller renders the final state.
    /// Disappeared IDs drop any in-flight pass.
    @discardableResult
    public mutating func observe(
        ids: [UUID],
        now: TimeInterval,
        reduceMotion: Bool
    ) -> [UUID] {
        var fresh: [UUID] = []
        let set = Set(ids)
        if reduceMotion {
            // Reduce Motion flipped on mid-pass: everything settles now.
            inFlight.removeAll()
        }
        for id in ids where !known.contains(id) {
            // Mark known IMMEDIATELY so duplicate IDs inside one
            // observe call collapse to a single fresh pass.
            known.insert(id)
            fresh.append(id)
            if !reduceMotion {
                inFlight[id] = now
            }
        }
        // Removal: a line that left the sheet stops its pass.
        for id in inFlight.keys where !set.contains(id) {
            inFlight.removeValue(forKey: id)
        }
        known.formUnion(ids)
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
