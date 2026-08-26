import Foundation

/// Pure, clock-injected appearance-animation state for answer-reference
/// capsules. The editor feeds it the sheet's current reference IDs (the
/// STABLE `AnswerReference.id` UUIDs, never marker locations) on every
/// commit; the IDs present at `seed` (sheet load, relaunch, sheet
/// switch) never animate, and only IDs that are NEWLY introduced
/// (double-click insertion, valid internal paste) get ONE appearance
/// pass. Live label/source updates and broken/recovered transitions
/// change neither the ID set nor any start time, so they never replay.
///
/// All time is caller-supplied (seconds), so the logic is deterministic
/// and unit-testable without AppKit, timers or the main thread.
public struct TokenAppearance: Equatable {
    /// The appearance pass duration (seconds): short, snappy.
    public static let duration: TimeInterval = 0.2
    /// Center scale at the start of the pass (the final scale is 1).
    public static let startScale: Double = 0.84

    /// IDs already present when this editor instance first saw the sheet
    /// (or seen before) — these never animate in this instance.
    private var known: Set<UUID>
    /// ID → start time (seconds) of its one in-flight appearance pass.
    public private(set) var inFlight: [UUID: TimeInterval]

    public init() {
        known = []
        inFlight = [:]
    }

    /// Registers the IDs that are already on the sheet when this editor
    /// instance attaches (load / relaunch / switch). They become known
    /// WITHOUT animating.
    public mutating func seed(ids: [UUID]) {
        known.formUnion(ids)
    }

    /// Observes the current ID set at `now`. Returns the IDs that are
    /// NEWLY introduced (in any order) — those are the ones that should
    /// play exactly one appearance pass. When `reduceMotion` is true no
    /// pass is scheduled at all (the caller renders the final state
    /// immediately). Disappeared IDs drop any in-flight pass.
    @discardableResult
    public mutating func observe(
        ids: [UUID],
        now: TimeInterval,
        reduceMotion: Bool
    ) -> [UUID] {
        var fresh: [UUID] = []
        let set = Set(ids)
        for id in ids where !known.contains(id) {
            fresh.append(id)
            if !reduceMotion {
                inFlight[id] = now
            }
        }
        // Removal: a token that left the sheet stops ticking.
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

    /// Center scale for a progress value (nil progress = final).
    public static func scale(progress: Double?) -> Double {
        guard let p = progress else { return 1 }
        return startScale + (1 - startScale) * p
    }

    /// Drawn opacity for a progress value (nil progress = final).
    public static func opacity(progress: Double?) -> Double {
        progress ?? 1
    }

    /// Short eased/snappy curve: fast out, settled end.
    public static func ease(_ t: Double) -> Double {
        let c = 1 - min(max(t, 0), 1)
        return 1 - c * c * c
    }
}
