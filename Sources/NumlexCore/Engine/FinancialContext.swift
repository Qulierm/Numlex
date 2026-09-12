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
/// national rate and display name. `ratePercent` is nil for a
/// manual-entry region (the United States has no automatic national
/// rate). Loaded from the versioned `NumlexTax` resource by
/// `TaxPresetCatalog`.
public struct TaxPreset: Equatable, Sendable {
    public let region: String
    public let name: String
    public let ratePercent: Double?
    public let note: String
    /// The official source that substantiates the rate (or, for the US
    /// manual row, that there is no national rate). Required and HTTPS.
    public let sourceTitle: String
    public let sourceURL: String

    public init(region: String, name: String, ratePercent: Double?, note: String,
                sourceTitle: String, sourceURL: String) {
        self.region = region
        self.name = name
        self.ratePercent = ratePercent
        self.note = note
        self.sourceTitle = sourceTitle
        self.sourceURL = sourceURL
    }
}

/// The thin API over the bundled resource catalog. There is no
/// hard-coded rate table in Swift: a missing/unverifiable resource
/// yields an EMPTY preset list and the phrases keep working with the
/// user's manual configuration.
public enum TaxPresets {
    public static var catalog: TaxPresetCatalog? { TaxPresetCatalog.shared }

    public static var version: String { catalog?.version ?? "unavailable" }

    public static var all: [TaxPreset] { catalog?.presets ?? [] }

    public static func preset(for region: String) -> TaxPreset? {
        catalog?.preset(for: region)
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
