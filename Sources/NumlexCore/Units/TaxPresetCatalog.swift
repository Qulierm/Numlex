import CryptoKit
import Foundation

// MARK: - Bundled sales-tax preset catalog (Package 2, Task 3)
//
// The versioned `tax-presets-2026.1` table: the official STANDARD
// national VAT/GST/consumption-tax rate per region (regional and
// sub-national rates are out of scope by design). The United States
// carries NO automatic rate (`ratePercent` nil) and always requires a
// manual entry. Generated reproducibly by `Scripts/generate-tax-presets.py`;
// the loader verifies the recorded SHA-256 and fails closed. Runtime is
// fully offline, and no rate or name is hard-coded in Swift.

public struct TaxPresetCatalog: Sendable, Equatable {

    public enum LoadError: Error, Equatable {
        case missingResource(String)
        case integrityFailure(String)
        case malformed(String)
    }

    public let version: String
    public let snapshotDate: String
    public let attribution: String
    public let license: String
    public let presets: [TaxPreset]

    public static let shared: TaxPresetCatalog? = TaxPresetCatalog.embedded()

    // MARK: loading

    public static func embedded() -> TaxPresetCatalog? {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let directory = bundle.url(forResource: "NumlexTax", withExtension: nil)
                ?? bundle.resourceURL?.appendingPathComponent("NumlexTax") else {
            return nil
        }
        return try? TaxPresetCatalog(contentsOf: directory)
    }

    public static var builtResourceDirectory: URL? {
        let candidates = [
            Bundle.main.resourceURL,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/arm64-apple-macosx/debug"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/debug"),
        ]
        for base in candidates {
            guard let base else { continue }
            let direct = base.appendingPathComponent("NumlexTax")
            if FileManager.default.fileExists(atPath: direct.path) { return direct }
            let nested = base.appendingPathComponent("Numlex_NumlexCore.bundle")
                .appendingPathComponent("NumlexTax")
            if FileManager.default.fileExists(atPath: nested.path) { return nested }
        }
        return nil
    }

    public init(contentsOf directory: URL) throws {
        let dataURL = directory.appendingPathComponent("tax-presets.json")
        let manifestURL = directory.appendingPathComponent("sources.json")
        guard let data = try? Data(contentsOf: dataURL) else {
            throw LoadError.missingResource("tax-presets.json")
        }
        guard let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any] else {
            throw LoadError.missingResource("sources.json")
        }
        let resources = manifest["resources"] as? [String: [String: String]]
        guard let expected = resources?["tax-presets.json"]?["sha256"] else {
            throw LoadError.integrityFailure("tax-presets.json")
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == expected else { throw LoadError.integrityFailure("tax-presets.json") }
        guard let decoded = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw LoadError.malformed("tax-presets.json")
        }
        version = decoded.version
        snapshotDate = decoded.snapshotDate
        attribution = decoded.attribution
        license = decoded.license
        presets = decoded.presets.map {
            TaxPreset(region: $0.region.uppercased(), name: $0.name,
                      ratePercent: $0.ratePercent, note: $0.note)
        }
        guard !presets.isEmpty else { throw LoadError.malformed("presets") }
        // Region keys are unique; a rate is either nil (manual) or a
        // finite 0...<100 percent.
        var seen = Set<String>()
        for preset in presets {
            guard seen.insert(preset.region).inserted else {
                throw LoadError.malformed("duplicate region \(preset.region)")
            }
            if let rate = preset.ratePercent {
                guard rate.isFinite, rate >= 0, rate < 100 else {
                    throw LoadError.malformed("rate \(preset.region)")
                }
            }
        }
    }

    /// A testable in-memory catalog.
    public init(version: String, snapshotDate: String, attribution: String,
                license: String, presets: [TaxPreset]) {
        self.version = version
        self.snapshotDate = snapshotDate
        self.attribution = attribution
        self.license = license
        self.presets = presets
    }

    // MARK: lookup

    public func preset(for region: String) -> TaxPreset? {
        let key = region.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !key.isEmpty else { return nil }
        return presets.first { $0.region == key }
    }

    private struct Payload: Decodable {
        let version: String
        let snapshotDate: String
        let attribution: String
        let license: String
        let presets: [Entry]

        struct Entry: Decodable {
            let region: String
            let name: String
            let ratePercent: Double?
            let note: String
        }
    }
}
