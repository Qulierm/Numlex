import Foundation

public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case en, ru, de, fr, it, zh
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var decimalPlaces: Int // 2..10
    public var fontSizeKey: String // ttt..tth maps to sizes
    public var language: AppLanguage
    public var sheetName: String
    public var lineNumbers: Bool
    public var fontColor: String // legacy

    public static let defaults = AppSettings(
        decimalPlaces: 7,
        fontSizeKey: "tf",
        language: .en,
        sheetName: "Sheet",
        lineNumbers: true,
        fontColor: "white"
    )

    public init(decimalPlaces: Int = 7, fontSizeKey: String = "tf", language: AppLanguage = .en, sheetName: String = "Sheet", lineNumbers: Bool = true, fontColor: String = "white") {
        self.decimalPlaces = decimalPlaces
        self.fontSizeKey = fontSizeKey
        self.language = language
        self.sheetName = sheetName
        self.lineNumbers = lineNumbers
        self.fontColor = fontColor
    }

    public var fontSize: Double {
        switch fontSizeKey {
        case "ttt": return 17
        case "tt": return 18
        case "tf": return 19
        case "tff": return 20
        case "ts": return 21
        case "tss": return 23
        case "te": return 25
        case "tn": return 27
        case "tth": return 29
        default: return 19
        }
    }
    public var lineHeight: Double { (fontSize * 1.6).rounded() }
}

public let fontSizeOptions: [(key: String, label: String)] = [
    ("ttt", "17"), ("tt", "18"), ("tf", "19"), ("tff", "20"), ("ts", "21"), ("tss", "23"), ("te", "25"), ("tn", "27"), ("tth", "29")
]
