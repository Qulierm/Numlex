import Foundation

public struct Rates: Codable, Equatable, Sendable {
    public var USD: Double?
    public var EUR: Double?
    public var EURUSD: Double?
    public init(USD: Double? = nil, EUR: Double? = nil, EURUSD: Double? = nil) {
        self.USD = USD
        self.EUR = EUR
        self.EURUSD = EURUSD
    }
}

public enum LineResult: Equatable, Sendable {
    case blank
    case skip
    case title(String)
    case number(value: Double, unit: String?)
    case variable(name: String, value: Double)
    case error(message: String)
}

/// One evaluated logical source line: its explicit 0-based index into
/// `source.components(separatedBy: "\n")` plus its result. `evaluateSheet`
/// returns exactly one SheetLine per logical line — leading, consecutive
/// and trailing blanks and `#` comments are `.blank`, so consumers can
/// bind rendered output to the exact editor line instead of to a
/// position after filtering.
public struct SheetLine: Equatable, Sendable {
    public var sourceLineIndex: Int
    public var result: LineResult
    public init(sourceLineIndex: Int, result: LineResult) {
        self.sourceLineIndex = sourceLineIndex
        self.result = result
    }
}
