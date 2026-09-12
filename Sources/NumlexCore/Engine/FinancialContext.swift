import Foundation

// MARK: - Financial context (Package 2)
//
// ONE explicit immutable context threaded through every evaluation path
// (line pipeline, sheet/resolve passes, token algebra, formatting and
// highlighting). It carries the app-global tax configuration and the
// optional bundled catalogs. There is no global mutable state: the app
// derives the context from the observable settings and passes it in,
// tests construct one directly.

/// The app-global sales-tax configuration (additive in `AppSettings`,
/// never in `.nlx`). All fields decode tolerantly: a missing key, a
/// malformed value or a wrong JSON type falls back to the default
/// instead of failing the store, and the payload version is NOT bumped.
public struct TaxPreferences: Codable, Equatable, Sendable {
    /// The selected preset region key (`"AU"`, `"GB"`, ...), or `""`
    /// for a fully manual/custom configuration. The preset only SEEDS
    /// name/rate at selection time; edits afterwards are user-owned.
    public var preset: String
    /// The accepted tax name (case-insensitive): the registered aliases
    /// plus this configured name.
    public var name: String
    /// The configured percent rate; nil = not configured (the lane then
    /// fails with the actionable "set sales tax in Settings → Tax"
    /// message).
    public var ratePercent: Double?

    public static let defaultName = "Sales Tax"
    public static let maxNameLength = 40

    public static let defaults = TaxPreferences(preset: "", name: defaultName,
                                                ratePercent: nil)

    public init(preset: String = "", name: String = defaultName,
                ratePercent: Double? = nil) {
        self.preset = preset
        self.name = TaxPreferences.sanitizedName(name)
        self.ratePercent = TaxPreferences.sanitizedRate(ratePercent)
    }

    /// A finite rate in [0, 100); nil stays nil.
    public static func sanitizedRate(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0, value < 100 else { return nil }
        return value
    }

    public static func sanitizedName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return defaultName }
        return String(trimmed.prefix(maxNameLength))
    }

    private enum CodingKeys: String, CodingKey { case preset, name, ratePercent }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        preset = ((try? c.decodeIfPresent(String.self, forKey: .preset)) ?? nil) ?? ""
        let rawName = ((try? c.decodeIfPresent(String.self, forKey: .name)) ?? nil) ?? TaxPreferences.defaultName
        name = TaxPreferences.sanitizedName(rawName)
        let rawRate = (try? c.decodeIfPresent(Double.self, forKey: .ratePercent)) ?? nil
        ratePercent = TaxPreferences.sanitizedRate(rawRate)
    }
}

/// One bundled sales-tax preset: a region key with its official standard
/// national rate and display name. US deliberately has NO automatic rate.
public struct TaxPreset: Equatable, Sendable {
    public let region: String
    public let name: String
    public let ratePercent: Double
    public let note: String

    public init(region: String, name: String, ratePercent: Double, note: String) {
        self.region = region
        self.name = name
        self.ratePercent = ratePercent
        self.note = note
    }
}

/// The versioned bundled preset table (standard national VAT/GST/consumption
/// rates; regional/US state rates are out of scope by design — the US row
/// requires a manual rate).
public enum TaxPresets {
    public static let version = "tax-presets-2026.1"

    public static let all: [TaxPreset] = [
        TaxPreset(region: "AU", name: "GST", ratePercent: 10,
                  note: "Australia GST, 10%"),
        TaxPreset(region: "GB", name: "VAT", ratePercent: 20,
                  note: "United Kingdom VAT, 20%"),
        TaxPreset(region: "DE", name: "VAT", ratePercent: 19,
                  note: "Germany VAT (Mehrwertsteuer), 19%"),
        TaxPreset(region: "NL", name: "VAT", ratePercent: 21,
                  note: "Netherlands VAT (BTW), 21%"),
        TaxPreset(region: "FR", name: "VAT", ratePercent: 20,
                  note: "France TVA, 20%"),
        TaxPreset(region: "IT", name: "VAT", ratePercent: 22,
                  note: "Italy IVA, 22%"),
        TaxPreset(region: "ES", name: "VAT", ratePercent: 21,
                  note: "Spain IVA, 21%"),
        TaxPreset(region: "IE", name: "VAT", ratePercent: 23,
                  note: "Ireland VAT, 23%"),
        TaxPreset(region: "AT", name: "VAT", ratePercent: 20,
                  note: "Austria VAT (USt), 20%"),
        TaxPreset(region: "BE", name: "VAT", ratePercent: 21,
                  note: "Belgium VAT (TVA/BTW), 21%"),
        TaxPreset(region: "PL", name: "VAT", ratePercent: 23,
                  note: "Poland VAT (PTU), 23%"),
        TaxPreset(region: "PT", name: "VAT", ratePercent: 23,
                  note: "Portugal IVA, 23%"),
        TaxPreset(region: "SE", name: "VAT", ratePercent: 25,
                  note: "Sweden VAT (moms), 25%"),
        TaxPreset(region: "DK", name: "VAT", ratePercent: 25,
                  note: "Denmark VAT (moms), 25%"),
        TaxPreset(region: "NO", name: "VAT", ratePercent: 25,
                  note: "Norway VAT (mva), 25%"),
        TaxPreset(region: "FI", name: "VAT", ratePercent: 25.5,
                  note: "Finland VAT (ALV), 25.5% (2024 standard rate)"),
        TaxPreset(region: "CH", name: "VAT", ratePercent: 8.1,
                  note: "Switzerland VAT (MWST), 8.1% (2024 standard rate)"),
        TaxPreset(region: "NZ", name: "GST", ratePercent: 15,
                  note: "New Zealand GST, 15%"),
        TaxPreset(region: "SG", name: "GST", ratePercent: 9,
                  note: "Singapore GST, 9% (2024)"),
        TaxPreset(region: "JP", name: "Consumption Tax", ratePercent: 10,
                  note: "Japan consumption tax, 10% standard"),
        TaxPreset(region: "CA", name: "GST", ratePercent: 5,
                  note: "Canada federal GST, 5% (provincial taxes excluded)"),
        TaxPreset(region: "IN", name: "GST", ratePercent: 18,
                  note: "India GST standard rate, 18%"),
        TaxPreset(region: "ZA", name: "VAT", ratePercent: 15,
                  note: "South Africa VAT, 15%"),
        TaxPreset(region: "MX", name: "VAT", ratePercent: 16,
                  note: "Mexico IVA, 16%"),
        TaxPreset(region: "US", name: "Sales Tax", ratePercent: 0,
                  note: "United States: no national rate — enter your local rate manually"),
    ]

    public static func preset(for region: String) -> TaxPreset? {
        all.first { $0.region.caseInsensitiveCompare(region) == .orderedSame }
    }
}

/// The immutable financial context: the app-global tax configuration plus
/// the optional bundled income-tax and CPI catalogs. Catalogs are loaded
/// once (fail-closed) and passed by value; nothing here is mutable global
/// state.
public struct FinancialContext: Equatable, Sendable {
    public var tax: TaxPreferences
    public var incomeTaxTables: IncomeTaxCatalog?
    public var cpi: CPICatalog?

    public init(tax: TaxPreferences = .defaults,
                incomeTaxTables: IncomeTaxCatalog? = nil,
                cpi: CPICatalog? = nil) {
        self.tax = tax
        self.incomeTaxTables = incomeTaxTables
        self.cpi = cpi
    }

    /// The bundled catalogs as they exist in the resource bundle.
    public static let bundled = FinancialContext(
        tax: .defaults,
        incomeTaxTables: IncomeTaxCatalog.shared,
        cpi: CPICatalog.shared)

    public static let defaults = FinancialContext()

    /// The context for the app's observable settings (bundled catalogs).
    public static func app(tax: TaxPreferences) -> FinancialContext {
        FinancialContext(tax: tax,
                         incomeTaxTables: IncomeTaxCatalog.shared,
                         cpi: CPICatalog.shared)
    }
}
