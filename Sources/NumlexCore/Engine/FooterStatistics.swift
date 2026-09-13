import Foundation

/// Package 7: the floating footer statistic. Additive and app-global
/// (missing/malformed decodes to `.sum`); never part of `.nlx`.
public enum FooterStatistic: String, Codable, CaseIterable, Equatable, Sendable {
    case sum
    case average
    case count
    case median

    /// Tolerant decode: an unknown raw value falls back to `.sum`.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = FooterStatistic(rawValue: raw) ?? .sum
    }
}

/// The footer statistics over the CURRENT `SheetFooterTotal`
/// contribution set: the broad dimension-agnostic magnitude
/// eligibility is preserved (and `.sum` is byte-for-byte the legacy
/// value), while derived aggregate rows (inline totals, subtotals,
/// grand totals, tag aggregates, dividers) never contribute.
public enum SheetFooterStatistics {
    public enum Value: Equatable, Sendable {
        /// A decimal statistic (sum/average/median).
        case value(Double)
        /// The exact integer row count.
        case count(Int)

        public var doubleValue: Double? {
            if case .value(let v) = self { return v }
            return nil
        }
    }

    /// The eligible contribution values, in display order.
    public static func contributions(_ lines: [SheetLine]) -> [Double] {
        var out: [Double] = []
        out.reserveCapacity(lines.count)
        for line in lines {
            if let c = SheetFooterTotal.contribution(of: line) { out.append(c) }
        }
        return out
    }

    /// The statistic, or nil when no row is eligible (nothing to show).
    public static func compute(_ lines: [SheetLine],
                               statistic: FooterStatistic) -> Value? {
        let values = contributions(lines)
        guard !values.isEmpty else { return nil }
        switch statistic {
        case .count:
            return .count(values.count)
        case .sum:
            var sum = 0.0
            for v in values {
                let next = sum + v
                guard next.isFinite else { return .value(next) }
                sum = next
            }
            return .value(sum)
        case .average:
            // Welford running mean: stable against avoidable overflow.
            var mean = 0.0
            var n = 0
            for v in values {
                n += 1
                mean += (v - mean) / Double(n)
            }
            return .value(mean)
        case .median:
            let sorted = values.sorted()
            let n = sorted.count
            if n % 2 == 1 { return .value(sorted[n / 2]) }
            let a = sorted[n / 2 - 1]
            let b = sorted[n / 2]
            return .value(a + (b - a) / 2)
        }
    }
}
