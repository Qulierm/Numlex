import Foundation

// MARK: - Explicit `as timespan` lane (temporal Task 3)
//
// The expression suffix `as timespan` forces the timespan presentation
// independently of the global/per-line notation:
//
//   5.5 minutes as timespan   -> 5 min 30 s
//   4.54 hours as timespan    -> 4 hours 32 minutes 24 seconds
//   72 days as timespan       -> 10 weeks 2 days
//
// The body must be a complete duration chain (`3h 5m 10s`), a laptime
// (`01:02:03`) or a clock (`3:30pm`); the shared typed parser
// (`DurationLiteral.parseChain`, with contextual glued m/s) decides
// what the chain means. An unparsable digit-bearing body is a strict
// error, never silence.
enum TimespanLane {

    static func tryLine(_ line: String,
                        context: NumberFormatContext,
                        temporal: TemporalContext,
                        unitContext: UnitContext) -> LineResult? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 120 else { return nil }
        guard trimmed.lowercased().hasSuffix(" as timespan") else { return nil }
        let body = String(trimmed.dropLast(" as timespan".count))
            .trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return nil }
        // 1. A whole-text duration chain (glued or spaced).
        if let chain = DurationLiteral.parseChain(body, unitContext: unitContext) {
            return .number(value: chain.seconds, unit: "s", kind: .timespan, fraction: nil)
        }
        // 2. A laptime (`01:02:03`) or a clock (`3:30pm`) value.
        if let lap = ClockLane.parseLaptime(body) {
            return .number(value: lap.seconds, unit: "s", kind: .timespan, fraction: nil)
        }
        if let clock = ClockLane.parseClockOperand(body) {
            let seconds = Double(clock.hour * 3600 + clock.minute * 60 + clock.second)
            return .number(value: seconds, unit: "s", kind: .timespan, fraction: nil)
        }
        if body.contains(where: { $0.isNumber }) {
            return .error(message: "Invalid expression")
        }
        return nil
    }
}
