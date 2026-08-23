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
        case "ttt": return 16
        case "tt": return 17
        case "tf": return 18
        case "tff": return 19
        case "ts": return 20
        case "tss": return 22
        case "te": return 24
        case "tn": return 26
        case "tth": return 28
        default: return 18
        }
    }
    public var lineHeight: Double { (fontSize * 1.6).rounded() }
}

public let fontSizeOptions: [(key: String, label: String)] = [
    ("ttt", "16"), ("tt", "17"), ("tf", "18"), ("tff", "19"), ("ts", "20"), ("tss", "22"), ("te", "24"), ("tn", "26"), ("tth", "28")
]
