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

    /// Starts a new logical line (occurrence counter resets).
    public func beginLine(_ key: String) {
        lineKey = key
        occurrence = 0
    }

    /// The next sample for the current line part, cached under the
    /// sheet + line + occurrence key.
    public func nextSample(low: Int64, high: Int64) -> Int64 {
        let key = "\(sheetID?.uuidString ?? "none")|\(lineKey)|\(occurrence)"
        occurrence += 1
        // The sample ALWAYS goes through the shared store (the epoch
        // cache), so duplicated passes see the same value even when a
        // deterministic test draw is injected.
        return store.sample(key: key, low: low, high: high, draw: explicitDraw)
    }
}

/// Package 7: whether an expression SOURCE contains a live rand call or
/// the natural random phrase. Used for the dynamic-row metadata (the
/// executed-result guard prevents marking skip/error rows).
public func lineUsesRandom(_ line: String) -> Bool {
    let lower = line.lowercased()
    if lower.contains("rand(") { return true }
    if lower.contains("random number between") { return true }
    return false
}

/// Package 7: the shared statistics implementations used by BOTH the
/// MathFunctions registry and the natural phrase lane.
public enum StatisticsFunctions {
    /// Population-free count.
    public static func count(_ args: [Double]) -> Double {
        Double(args.count)
    }

    /// Sorted median with an overflow-safe midpoint.
    public static func median(_ args: [Double]) -> Double? {
        guard !args.isEmpty else { return nil }
        let sorted = args.sorted()
        let n = sorted.count
        if n % 2 == 1 { return sorted[n / 2] }
        let a = sorted[n / 2 - 1]
        let b = sorted[n / 2]
        return a + (b - a) / 2
    }

    /// SAMPLE standard deviation (n-1), stable Welford algorithm.
    public static func stdev(_ args: [Double]) -> Double? {
        guard args.count >= 2 else { return nil }
        var mean = 0.0
        var m2 = 0.0
        var n = 0
        for x in args {
            n += 1
            let delta = x - mean
            mean += delta / Double(n)
            m2 += delta * (x - mean)
        }
        guard n >= 2, m2.isFinite, mean.isFinite else { return nil }
        let variance = m2 / Double(n - 1)
        guard variance.isFinite, variance >= 0 else { return nil }
        return variance.squareRoot()
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
