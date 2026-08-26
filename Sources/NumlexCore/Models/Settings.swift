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
        decimalPlaces: 10,
        fontSizeKey: "tf",
        language: .en,
        sheetName: "Sheet",
        lineNumbers: true,
        fontColor: "white"
    )

    public init(decimalPlaces: Int = 10, fontSizeKey: String = "tf", language: AppLanguage = .en, sheetName: String = "Sheet", lineNumbers: Bool = true, fontColor: String = "white") {
        self.decimalPlaces = decimalPlaces
        self.fontSizeKey = fontSizeKey
        self.language = language
        self.sheetName = sheetName
        self.lineNumbers = lineNumbers
        self.fontColor = fontColor
    }

    public var fontSize: Double {
        // Every level is exactly 1 pt above the previous scale so that
        // persisted keys keep their relative size and both the editor
        // body and the answer column grow together.
        switch fontSizeKey {
        case "ttt": return 18
        case "tt": return 19
        case "tf": return 20
        case "tff": return 21
        case "ts": return 22
        case "tss": return 24
        case "te": return 26
        case "tn": return 28
        case "tth": return 30
        default: return 20
        }
    }
    /// Derives the line height from the EFFECTIVE font size so TextKit
    /// metrics and the answer column stay 1:1 at every settings level.
    public var lineHeight: Double { (fontSize * 1.6).rounded() }
}

public let fontSizeOptions: [(key: String, label: String)] = [
    ("ttt", "18"), ("tt", "19"), ("tf", "20"), ("tff", "21"), ("ts", "22"), ("tss", "24"), ("te", "26"), ("tn", "28"), ("tth", "30")
]
