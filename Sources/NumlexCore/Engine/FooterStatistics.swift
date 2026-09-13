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
            guard let mean = StatisticsFunctions.average(values) else {
                return nil
            }
            return .value(mean)
        case .median:
            guard let median = StatisticsFunctions.median(values) else {
                return nil
            }
            return .value(median)
        }
    }
}

/// Package 7: the ONE footer-statistic menu contract — the display
/// order and the single checked entry. Pure so the UI construction and
/// its tests share the same source of truth.
public enum FooterStatisticMenu {
    /// The menu order (also the `allCases` order).
    public static let order: [FooterStatistic] = FooterStatistic.allCases

    /// Whether `statistic` is the checked entry for the current value.
    public static func isChecked(_ statistic: FooterStatistic,
                              current: FooterStatistic) -> Bool {
        statistic == current
    }
}
