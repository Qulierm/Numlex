import Foundation

// MARK: - Special-date lane (temporal Task 6)
//
// The `days until <holiday>` query, sitting beside the ordinary date
// lane: the next occurrence is this year's date when it is still in the
// future, otherwise next year's. Unknown holiday names are a strict
// error; the lane never touches date prefixes (those stay in
// DateArithmetic, which understands `Easter 2027` and `Christmas`).
enum SpecialDateLane {

    static func tryLine(_ line: String,
                        context: NumberFormatContext,
                        temporal: TemporalContext,
                        unitContext: UnitContext) -> LineResult? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 80 else { return nil }
        let lower = trimmed.lowercased()
        for prefix in ["days until ", "days to ", "days till ", "days before "] {
            guard lower.hasPrefix(prefix) else { continue }
            let name = String(trimmed.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return .error(message: "Unknown holiday") }
            guard let days = SpecialDateCatalog.daysUntil(named: name,
                                                          from: temporal.now,
                                                          calendar: temporal.calendar) else {
                return .error(message: "Unknown holiday")
            }
            return .number(value: Double(days), unit: "days", kind: .plain, fraction: nil)
        }
        return nil
    }
}
