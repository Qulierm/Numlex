import Foundation

// MARK: - R84: cooking ingredient densities
//
// The approximate pack/scoop densities behind the cooking-density
// conversions (`200 g of flour to ml`, `1 cup of honey to g`). The
// values are DELIBERATELY APPROXIMATE (they reproduce the standard
// US-baking cup tables: e.g. 1 cup of all-purpose flour ≈ 125 g) and
// are pinned by the `version` string so a future re-measurement is a
// visible, reviewable change — never a silent drift.

public enum CookingDensities {
    /// The catalog version (bump on any value change).
    public static let version = "r84-1"

    /// One ingredient row: the input name (space/hyphen-insensitive),
    /// the display label, the approximate density in kg/m³ and a short
    /// note of what the value represents.
    public struct Entry: Equatable, Sendable {
        public let name: String
        public let label: String
        public let kgPerM3: Double
        public let note: String
        public init(name: String, label: String, kgPerM3: Double, note: String) {
            self.name = name
            self.label = label
            self.kgPerM3 = kgPerM3
            self.note = note
        }
    }

    /// The versioned table (input order is display order).
    public static let entries: [Entry] = [
        Entry(name: "water", label: "water", kgPerM3: 1_000,
              note: "1 cup ≈ 237 g"),
        Entry(name: "flour", label: "all-purpose flour", kgPerM3: 528.3,
              note: "1 cup ≈ 125 g (spooned, leveled)"),
        Entry(name: "sugar", label: "granulated sugar", kgPerM3: 845.4,
              note: "1 cup ≈ 200 g"),
        Entry(name: "brownsugar", label: "brown sugar (packed)", kgPerM3: 930.3,
              note: "1 cup ≈ 220 g"),
        Entry(name: "icingsugar", label: "powdered sugar", kgPerM3: 507.2,
              note: "1 cup ≈ 120 g"),
        Entry(name: "salt", label: "table salt", kgPerM3: 1_153.9,
              note: "1 cup ≈ 273 g"),
        Entry(name: "butter", label: "butter", kgPerM3: 959.4,
              note: "1 cup ≈ 227 g"),
        Entry(name: "honey", label: "honey", kgPerM3: 1_437.1,
              note: "1 cup ≈ 340 g"),
        Entry(name: "milk", label: "whole milk", kgPerM3: 1_031.3,
              note: "1 cup ≈ 244 g"),
        Entry(name: "oil", label: "vegetable oil", kgPerM3: 921.4,
              note: "1 cup ≈ 218 g"),
        Entry(name: "rice", label: "white rice (dry)", kgPerM3: 782.0,
              note: "1 cup ≈ 185 g uncooked"),
        Entry(name: "cornstarch", label: "cornstarch", kgPerM3: 541.0,
              note: "1 cup ≈ 128 g"),
        Entry(name: "oats", label: "rolled oats (dry)", kgPerM3: 338.2,
              note: "1 cup ≈ 80 g"),
        Entry(name: "cocoa", label: "cocoa powder (sifted)", kgPerM3: 359.3,
              note: "1 cup ≈ 85 g"),
        Entry(name: "chocolate", label: "chocolate chips", kgPerM3: 718.5,
              note: "1 cup ≈ 170 g"),
        Entry(name: "peanutbutter", label: "peanut butter", kgPerM3: 1_090.5,
              note: "1 cup ≈ 258 g"),
        Entry(name: "creamcheese", label: "cream cheese", kgPerM3: 976.4,
              note: "1 cup ≈ 231 g"),
        Entry(name: "yogurt", label: "plain yogurt", kgPerM3: 1_035.6,
              note: "1 cup ≈ 245 g"),
        Entry(name: "applesauce", label: "applesauce", kgPerM3: 1_031.3,
              note: "1 cup ≈ 244 g"),
        Entry(name: "cornmeal", label: "cornmeal", kgPerM3: 613.1,
              note: "1 cup ≈ 145 g"),
        Entry(name: "yeast", label: "dry yeast", kgPerM3: 450,
              note: "1 cup ≈ 107 g (very light)")
    ]

    /// Looks an ingredient up by INPUT text: lowercased with spaces and
    /// hyphens removed (`brown sugar`, `brown-sugar` and `brownsugar`
    /// all resolve).
    public static func entry(named raw: String) -> Entry? {
        let key = String(raw.lowercased()
            .filter { $0 == " " || $0 == "-" ? false : true })
        guard !key.isEmpty else { return nil }
        return entries.first { $0.name == key }
    }

    /// The approximate density in kg/m³ (nil for unknown ingredients).
    public static func kgPerM3(named raw: String) -> Double? {
        entry(named: raw)?.kgPerM3
    }
}
