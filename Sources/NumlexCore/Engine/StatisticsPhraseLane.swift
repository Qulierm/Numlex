import Foundation

/// Package 7: the strict natural statistics forms, routed through the
/// SAME shared implementations as the MathFunctions registry:
///
///   median of <list>            (>= 1 value)
///   count of <list>             (>= 1 value)
///   standard deviation of <list> (>= 2 values, SAMPLE n-1)
///   random number between X and Y (finite exact integer bounds)
///
/// Lists use the active argument separator (`,` or `;`); the numbers use
/// the shared locale-aware parser. Anything else (prose, trailing
/// garbage, an empty list, invalid bounds) is not this lane.
public enum StatisticsPhraseLane {
    public static func tryLine(_ line: String,
                               context: NumberFormatContext,
                               random: RandomEvaluationContext?) -> LineResult? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()

        // random number between X and Y
        if lower.hasPrefix("random number between ") {
            guard let random else { return nil }
            let rest = String(trimmed.dropFirst("random number between ".count))
            guard let sep = rest.range(of: " and ", options: .caseInsensitive) else {
                return .error(message: "Invalid expression")
            }
            let lowText = String(rest[..<sep.lowerBound])
            let highText = String(rest[sep.upperBound...])
            guard let low = FinancialPhraseLane.parseNumber(lowText, context: context),
                  let high = FinancialPhraseLane.parseNumber(highText, context: context),
                  let (lo, hi) = StatisticsFunctions.randBounds(low, high) else {
                return .error(message: "Invalid expression")
            }
            return .number(value: Double(random.nextSample(low: lo, high: hi)), unit: nil)
        }

        // <stat> of <list>
        let forms: [(String, String)] = [
            ("median of ", "median"),
            ("count of ", "count"),
            ("standard deviation of ", "stdev"),
        ]
        for (prefix, name) in forms where lower.hasPrefix(prefix) {
            let listText = String(trimmed.dropFirst(prefix.count))
            let values = parseList(listText, context: context)
            guard !values.isEmpty else { return .error(message: "Invalid expression") }
            switch name {
            case "count":
                return .number(value: StatisticsFunctions.count(values), unit: nil)
            case "median":
                guard let m = StatisticsFunctions.median(values) else {
                    return .error(message: "Invalid expression")
                }
                return .number(value: roundResult(m, decimalPlaces: 10), unit: nil)
            default:
                guard let sd = StatisticsFunctions.stdev(values), sd.isFinite else {
                    return .error(message: "Invalid expression")
                }
                return .number(value: roundResult(sd, decimalPlaces: 10), unit: nil)
            }
        }
        return nil
    }

    /// The numeric argument list: values separated by the active
    /// argument separator (`,`/`;`), every entry a strict number.
    static func parseList(_ raw: String, context: NumberFormatContext) -> [Double] {
        // The ACTIVE argument separator only: in decimal-comma modes the
        // comma is the decimal mark, so lists use `;`.
        let separator = context.argumentSeparator.isEmpty ? "," : context.argumentSeparator
        let pieces = raw.components(separatedBy: separator)
        var out: [Double] = []
        for piece in pieces {
            let trimmed = piece.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  let v = FinancialPhraseLane.parseNumber(trimmed, context: context) else {
                return []
            }
            out.append(v)
        }
        return out
    }
}
