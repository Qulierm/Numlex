import Foundation

/// Package 7: EPHEMERAL random samples for one semantic evaluation
/// epoch. The store is never persisted and never enters the store or
/// `.nlx`: it holds the samples drawn for `rand`/`random number`
/// results so duplicated resolve/classifier/body passes, scrolling,
/// hover and format-only changes see the SAME value. A semantic source
/// edit, a fresh load/sheet activation, or the explicit Recalculate
/// command clears it (a new epoch).
public final class RandomSampleStore: @unchecked Sendable {
    private var samples: [String: Int64] = [:]
    private let lock = NSLock()
    /// Default entropy: the system generator, unbiased over the range.
    private var generator = SystemRandomNumberGenerator()

    public init() {}

    /// The sample for `key`, drawn once with the system generator on
    /// first use (inclusive bounds).
    func sample(key: String, low: Int64, high: Int64,
                draw: ((Int64, Int64) -> Int64)? = nil) -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        if let v = samples[key] { return v }
        let v = draw?(low, high) ?? Int64.random(in: low...high, using: &generator)
        samples[key] = v
        return v
    }

    /// Clears every sample (a new semantic epoch).
    public func clear() {
        lock.lock()
        samples.removeAll()
        lock.unlock()
    }

    public var sampleCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return samples.count
    }
}

/// Package 7: the immutable/inout random evaluation context threaded
/// through the evaluation paths. `sheetID` + the current LINE STABLE
/// ID + the per-line occurrence form the sample key, so the same
/// semantic evaluation epoch resolves identically no matter how many
/// passes run.
public final class RandomEvaluationContext: @unchecked Sendable {
    public let store: RandomSampleStore
    public let sheetID: UUID?
    /// Set by the sheet loops before each line (stable line UUID, or
    /// the 1-based index when no stable IDs exist).
    public var lineKey: String
    private var occurrence = 0
    /// Package 7 (execution-aware dynamic detection): set by
    /// `nextSample`, reset by `beginLine`. Only an ACTUALLY EXECUTED
    /// `rand`/random phrase marks the line dynamic — lazy unselected
    /// branches, invalid text and whitespace variants never do.
    private var consumedRandom = false
    /// Deterministic test override: draw in `low...high`.
    private let explicitDraw: ((Int64, Int64) -> Int64)?

    public init(sheetID: UUID?,
                lineKey: String = "1",
                store: RandomSampleStore = RandomSampleStore(),
                draw: ((Int64, Int64) -> Int64)? = nil) {
        self.sheetID = sheetID
        self.lineKey = lineKey
        self.store = store
        self.explicitDraw = draw
    }

    /// True when the CURRENT line's last evaluation actually consumed
    /// at least one random sample (the execution-aware dynamic flag).
    public var didConsumeRandom: Bool { consumedRandom }

    /// Starts a new logical line (occurrence counter and the
    /// execution-aware dynamic flag reset).
    public func beginLine(_ key: String) {
        lineKey = key
        occurrence = 0
        consumedRandom = false
    }

    /// The next sample for the current line part, cached under the
    /// sheet + line + occurrence key.
    public func nextSample(low: Int64, high: Int64) -> Int64 {
        consumedRandom = true
        let key = "\(sheetID?.uuidString ?? "none")|\(lineKey)|\(occurrence)"
        occurrence += 1
        // The sample ALWAYS goes through the shared store (the epoch
        // cache), so duplicated passes see the same value even when a
        // deterministic test draw is injected.
        return store.sample(key: key, low: low, high: high, draw: explicitDraw)
    }
}

/// Package 7: the shared statistics implementations used by BOTH the
/// MathFunctions registry and the natural phrase lane.
public enum StatisticsFunctions {
    /// Population-free count.
    public static func count(_ args: [Double]) -> Double {
        Double(args.count)
    }

    /// The ONE overflow-safe midpoint shared by the median paths
    /// (registry, tag aggregates, footer). The difference path is used
    /// whenever it is finite (the common case); otherwise the halves
    /// are added — `a + (b - a)/2` would return `inf` for the finite
    /// pair `(-1e308, +1e308)` while `a/2 + b/2` is exactly 0.
    public static func midpoint(_ a: Double, _ b: Double) -> Double {
        let diff = b - a
        if diff.isFinite { return a + diff / 2 }
        return a / 2 + b / 2
    }

    /// Sorted median with the shared overflow-safe midpoint.
    public static func median(_ args: [Double]) -> Double? {
        guard !args.isEmpty else { return nil }
        let sorted = args.sorted()
        let n = sorted.count
        if n % 2 == 1 { return sorted[n / 2] }
        return midpoint(sorted[n / 2 - 1], sorted[n / 2])
    }

    /// The overflow-safe finite mean (the SAME `MathFunctions.stableAverage`
    /// the registry uses), or nil for an empty/failed input.
    public static func average(_ args: [Double]) -> Double? {
        guard !args.isEmpty else { return nil }
        return try? MathFunctions.stableAverage(args)
    }

    /// SAMPLE standard deviation (n-1): a scaled two-pass algorithm
    /// around the stable mean. Welford's raw `delta * (x - mean)`
    /// squares a delta near 1e308 and overflows even when the sample
    /// stdev is finite; scaling every deviation by the largest
    /// |x - mean| keeps every intermediate bounded, and the result is
    /// rejected only when it is genuinely non-finite.
    public static func stdev(_ args: [Double]) -> Double? {
        let n = args.count
        guard n >= 2 else { return nil }
        guard let mean = average(args), mean.isFinite else { return nil }
        var scale = 0.0
        for x in args {
            let delta = abs(x - mean)
            guard delta.isFinite else { return nil }
            scale = max(scale, delta)
        }
        if scale == 0 { return 0 }
        var ssq = 0.0
        for x in args {
            let d = (x - mean) / scale
            guard d.isFinite else { return nil }
            ssq += d * d
        }
        let variance = ssq / Double(n - 1)
        guard variance.isFinite, variance >= 0 else { return nil }
        let sd = scale * variance.squareRoot()
        guard sd.isFinite else { return nil }
        return sd
    }

    /// The safe inclusive integer domain (exact as Double).
    public static let maxRandomMagnitude: Int64 = 9_007_199_254_740_992

    /// Validates + converts the two rand bounds.
    public static func randBounds(_ low: Double, _ high: Double) -> (Int64, Int64)? {
        guard low.isFinite, high.isFinite,
              low == low.rounded(), high == high.rounded(),
              abs(low) <= Double(maxRandomMagnitude),
              abs(high) <= Double(maxRandomMagnitude),
              low <= high else { return nil }
        return (Int64(low), Int64(high))
    }
}
