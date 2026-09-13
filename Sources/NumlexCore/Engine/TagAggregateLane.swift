import Foundation

/// Package 7: the strict tag-aggregate commands.
///
/// Grammar (case-insensitive keywords, exactly ONE queried tag):
///   `total of #tag` · `average of #tag` · `count of #tag` ·
///   `median of #tag`
///
/// The queried `#tag` is a terminal tag of the row (the shared
/// SheetLineAnalysis strips it), so the evaluation projection is the
/// bare keyword phrase and `analysis.tags` must hold exactly one tag.
/// Any trailing garbage, multiple query tags and invalid tag
/// identifiers reject the line.
public enum TagAggregateKind: Equatable, Sendable {
    case total
    case average
    case count
    case median
}

public struct TagAggregateCommand: Equatable, Sendable {
    public let kind: TagAggregateKind
    /// The NFC + case-folded tag key to query.
    public let tagKey: String
    /// The source spelling of the queried tag (for diagnostics/spans).
    public let tagSpelling: String

    public init(kind: TagAggregateKind, tagKey: String, tagSpelling: String) {
        self.kind = kind
        self.tagKey = tagKey
        self.tagSpelling = tagSpelling
    }
}

public enum TagAggregateLane {
    /// Parses a strict tag-aggregate command from the shared analysis.
    public static func parse(_ analysis: SheetLineAnalysis) -> TagAggregateCommand? {
        guard analysis.kind == .expression, analysis.tags.count == 1 else { return nil }
        let tokens = analysis.evaluationProjection
            .trimmingCharacters(in: .whitespaces)
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .map { $0.lowercased() }
        guard tokens.count == 2, tokens[1] == "of" else { return nil }
        let kind: TagAggregateKind
        switch tokens[0] {
        case "total": kind = .total
        case "average": kind = .average
        case "count": kind = .count
        case "median": kind = .median
        default: return nil
        }
        let tag = analysis.tags[0]
        return TagAggregateCommand(kind: kind, tagKey: tag.key,
                                   tagSpelling: tag.spelling)
    }
}

/// Package 7: the per-tag aggregate state for ONE sheet pass. It sees
/// only the eligible tagged rows STRICTLY ABOVE the current line in the
/// CURRENT segment (a divider clears it); a row with several tags
/// contributes once to each tag.
public struct TagAggregateState: Sendable {
    private struct Bucket {
        var count: Int = 0
        var sum: Double = 0
        var overflowed = false
        /// Welford running mean (overflow-stable average).
        var mean: Double = 0
        var values: [Double] = []
    }

    private var buckets: [String: Bucket] = [:]

    public init() {}

    /// A divider ends the current tag segment.
    public mutating func boundary() {
        buckets.removeAll(keepingCapacity: true)
    }

    /// Feeds one completed row's tags (only when the row is eligible
    /// under the shared source-aware contract and is not derived).
    public mutating func observe(tags: [LineTag], value: Double?) {
        guard let value, value.isFinite else { return }
        for tag in tags {
            var bucket = buckets[tag.key] ?? Bucket()
            bucket.count += 1
            if !bucket.overflowed {
                let next = bucket.sum + value
                if next.isFinite {
                    bucket.sum = next
                } else {
                    bucket.overflowed = true
                }
            }
            // Welford mean: stable against avoidable overflow.
            bucket.mean += (value - bucket.mean) / Double(bucket.count)
            bucket.values.append(value)
            buckets[tag.key] = bucket
        }
    }

    /// Resolves one query. Empty total/count = 0; empty average/median
    /// is the quiet generic error; total overflow is the same error.
    public func resolve(_ command: TagAggregateCommand,
                        decimalPlaces: Int) -> LineResult {
        let bucket = buckets[command.tagKey] ?? Bucket()
        switch command.kind {
        case .count:
            return .number(value: Double(bucket.count), unit: nil)
        case .total:
            guard !bucket.overflowed else {
                return .error(message: InlineTotal.overflowMessage)
            }
            return .number(value: roundResult(bucket.sum, decimalPlaces: decimalPlaces),
                           unit: nil)
        case .average:
            guard bucket.count > 0 else {
                return .error(message: InlineTotal.overflowMessage)
            }
            return .number(value: roundResult(bucket.mean, decimalPlaces: decimalPlaces),
                           unit: nil)
        case .median:
            guard !bucket.values.isEmpty else {
                return .error(message: InlineTotal.overflowMessage)
            }
            var sorted = bucket.values.sorted()
            let n = sorted.count
            let median: Double
            if n % 2 == 1 {
                median = sorted[n / 2]
            } else {
                let a = sorted[n / 2 - 1]
                let b = sorted[n / 2]
                // Overflow-safe midpoint.
                median = a + (b - a) / 2
            }
            _ = sorted.popLast()
            return .number(value: roundResult(median, decimalPlaces: decimalPlaces),
                           unit: nil)
        }
    }

    /// How many eligible tagged rows the current segment has for a key.
    public func count(for tagKey: String) -> Int {
        buckets[tagKey]?.count ?? 0
    }
}
