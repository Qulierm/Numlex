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

public struct SheetLine: Equatable, Sendable {
    public var result: LineResult
    public init(_ result: LineResult) { self.result = result }
}
