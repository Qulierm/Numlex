import AppKit
import Foundation
import NumlexCore

/// The 4.9.2 packaged-app crash fix: the centralized `ResourceLocator`
/// (no `Bundle.module`, no developer-absolute paths, fail-closed nil)
/// replaces the generated SwiftPM accessor whose hardcoded build path +
/// fatalError trapped the packaged app on first launch.
///
/// Covers: pure candidate generation/dedup, the full lookup order with
/// temp layouts (standard packaged, SwiftPM root, executable sibling,
/// direct layout), precedence, missing/non-directory/hostile inputs,
/// dataset resolution, production process resolution, every catalog
/// loading through the locator, integrity fail-closed behavior (corrupt
/// copy), and the source/packaging contracts.
private func locatorSource(_ relative: String) throws -> String {
    var url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    for _ in 0..<6 {
        let candidate = url.appendingPathComponent(relative)
        if FileManager.default.fileExists(atPath: candidate.path) {
            return try String(contentsOf: candidate, encoding: .utf8)
        }
        url.deleteLastPathComponent()
    }
    throw CaseFailure(message: "source not found: \(relative)", location: "ResourceLocator")
}

/// A fresh temp directory for fake layouts (cleaned up by the caller).
private func locatorTempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("numlex-locator-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// A fake SwiftPM-style bundle under `root` carrying empty dataset
/// directories (enough for the locator; not enough for catalog
/// integrity, which is tested with the REAL built bundle).
private func makeFakeBundle(under root: URL, datasets: [String]) throws -> URL {
    let bundle = root.appendingPathComponent(ResourceLocator.coreBundleName)
    try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
    for name in datasets {
        try FileManager.default.createDirectory(
            at: bundle.appendingPathComponent(name), withIntermediateDirectories: true)
    }
    return bundle
}

public let resourceLocatorCases: [EngineCase] = [

    // MARK: - pure candidate generation

    EngineCase("locator-candidate-generation-order-and-dedup") {
        let a = URL(fileURLWithPath: "/fake/resources", isDirectory: true)
        let b = URL(fileURLWithPath: "/fake/root", isDirectory: true)
        let d = URL(fileURLWithPath: "/fake/direct.bundle", isDirectory: true)
        let got = ResourceLocator.candidateBundleURLs(baseURLs: [a, a, nil, b], directBundleURL: d)
        let want = [
            a.appendingPathComponent(ResourceLocator.coreBundleName),
            b.appendingPathComponent(ResourceLocator.coreBundleName),
            d,
        ].map { $0.standardizedFileURL.resolvingSymlinksInPath() }
        let gotC = got.map { $0.standardizedFileURL.resolvingSymlinksInPath() }
        try expectEqual(gotC, want, "order preserved, duplicates and nils dropped, direct last")
        // No base at all: only the direct layout (or nothing).
        try expectEqual(
            ResourceLocator.candidateBundleURLs(baseURLs: [], directBundleURL: d).count, 1,
            "direct-only layout")
        try expectEqual(ResourceLocator.candidateBundleURLs(baseURLs: []).count, 0,
                        "no layout at all -> no candidates")
    },

    // MARK: - resolution order with temp layouts

    EngineCase("locator-resolve-order-standard-packaged-wins") {
        let root = try locatorTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let resourcesBase = root.appendingPathComponent("resources", isDirectory: true)
        let rootBase = root.appendingPathComponent("approot", isDirectory: true)
        try FileManager.default.createDirectory(at: resourcesBase, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootBase, withIntermediateDirectories: true)
        _ = try makeFakeBundle(under: resourcesBase, datasets: ["NumlexTimezones"])
        _ = try makeFakeBundle(under: rootBase, datasets: ["NumlexTimezones"])
        // The STANDARD packaged location (Bundle.main.resourceURL, first
        // in the documented order) must win over a root-level twin.
        let resolved = ResourceLocator.resolveBundle(
            candidates: ResourceLocator.candidateBundleURLs(baseURLs: [resourcesBase, rootBase]))
        try expectEqual(resolved?.standardizedFileURL,
                        (resourcesBase.appendingPathComponent(ResourceLocator.coreBundleName)
                            .standardizedFileURL),
                        "resourceURL location precedes the app-root location")
    },

    EngineCase("locator-resolve-swiftpm-root-layout") {
        let root = try locatorTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let empty = root.appendingPathComponent("empty", isDirectory: true)
        let withBundle = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: withBundle, withIntermediateDirectories: true)
        let bundle = try makeFakeBundle(under: withBundle, datasets: ["NumlexTax"])
        // No bundle at the first base; the SwiftPM-style root (second)
        // provides it.
        let resolved = ResourceLocator.resolveBundle(
            candidates: ResourceLocator.candidateBundleURLs(baseURLs: [empty, withBundle]))
        try expectEqual(resolved?.standardizedFileURL, bundle.standardizedFileURL,
                        "the first base that HAS the bundle wins")
    },

    EngineCase("locator-resolve-executable-sibling-layout") {
        let root = try locatorTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let exec = root.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: exec, withIntermediateDirectories: true)
        let bundle = try makeFakeBundle(under: exec, datasets: ["NumlexCPI"])
        let resolved = ResourceLocator.resolveBundle(
            candidates: ResourceLocator.candidateBundleURLs(baseURLs: [exec]))
        try expectEqual(resolved?.standardizedFileURL, bundle.standardizedFileURL,
                        "a sibling of the executable satisfies the lookup")
    },

    EngineCase("locator-resolve-direct-layout") {
        let root = try locatorTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let direct = root.appendingPathComponent("datasets", isDirectory: true)
        try FileManager.default.createDirectory(
            at: direct.appendingPathComponent("NumlexHolidays"), withIntermediateDirectories: true)
        let resolved = ResourceLocator.resolveBundle(
            candidates: ResourceLocator.candidateBundleURLs(baseURLs: [root], directBundleURL: direct))
        try expectEqual(resolved?.standardizedFileURL, direct.standardizedFileURL,
                        "the direct layout is accepted")
        let dataset = ResourceLocator.datasetDirectory(named: "NumlexHolidays", in: direct)
        try expectEqual(dataset?.standardizedFileURL,
                        direct.appendingPathComponent("NumlexHolidays").standardizedFileURL,
                        "dataset directory resolved inside the direct layout")
    },

    // MARK: - fail-closed: missing, non-directory, hostile

    EngineCase("locator-fail-closed-missing-and-file-candidates") {
        let root = try locatorTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent(ResourceLocator.coreBundleName)
        FileManager.default.createFile(atPath: file.path, contents: Data("not a directory".utf8))
        let candidates = [
            root.appendingPathComponent("no-such-bundle"), // missing
            file, // a plain FILE named like a bundle
        ]
        try expect(ResourceLocator.resolveBundle(candidates: candidates) == nil,
                   "missing path and plain-file candidate are both skipped (nil, no trap)")
        try expect(ResourceLocator.resolveBundle(candidates: []) == nil,
                   "an empty candidate list resolves to nil")
    },

    EngineCase("locator-fail-closed-hostile-input") {
        let root = try locatorTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        // Paths that escape the layout but do not exist: skipped.
        let escaping = [
            root.appendingPathComponent("../../outside/\(ResourceLocator.coreBundleName)"),
            URL(fileURLWithPath: "/nonexistent/nowhere/\(ResourceLocator.coreBundleName)"),
        ]
        try expect(ResourceLocator.resolveBundle(candidates: escaping) == nil,
                   "hostile/nonexistent candidates never resolve")
        // A direct layout pointing at a file is not a bundle.
        let file = root.appendingPathComponent("plain-file")
        FileManager.default.createFile(atPath: file.path, contents: Data("x".utf8))
        try expect(ResourceLocator.resolveBundle(
            candidates: ResourceLocator.candidateBundleURLs(baseURLs: [], directBundleURL: file)) == nil,
                   "a file is never accepted as a bundle")
        // datasetDirectory on an absent dataset is nil, not a trap.
        let bundle = try makeFakeBundle(under: root, datasets: ["NumlexTimezones"])
        try expect(ResourceLocator.datasetDirectory(named: "NumlexGhost", in: bundle) == nil,
                   "an absent dataset directory is nil")
        // A FILE with a dataset name is not a dataset directory.
        FileManager.default.createFile(
            atPath: bundle.appendingPathComponent("NumlexGhost").path, contents: Data("x".utf8))
        try expect(ResourceLocator.datasetDirectory(named: "NumlexGhost", in: bundle) == nil,
                   "a file named like a dataset is skipped")
    },

    EngineCase("locator-production-process-resolution") {
        // The test process runs next to (or from the repo root of) the
        // .build products, so the production lookup must find the REAL
        // built bundle here — and a dataset inside it.
        guard let bundle = ResourceLocator.resolveCoreBundle() else {
            throw CaseFailure(message: "production lookup found no bundle on the dev host",
                              location: "ResourceLocator")
        }
        try expect(FileManager.default.fileExists(atPath: bundle.path, isDirectory: nil),
                   "the resolved bundle is a real directory")
        guard let dataset = ResourceLocator.coreDatasetDirectory(named: "NumlexTimezones") else {
            throw CaseFailure(message: "timezone dataset not found through the production lookup",
                              location: "ResourceLocator")
        }
        try expect(FileManager.default.fileExists(
            atPath: dataset.appendingPathComponent("iana-zones.tsv").path),
            "the resolved timezone dataset carries its data file")
    },

    // MARK: - catalogs through the locator (integrity preserved)

    EngineCase("catalogs-load-through-locator") {
        // All five catalogs load through the centralized locator with
        // their integrity checks (required files + SHA-256) intact.
        guard ResourceLocator.resolveCoreBundle() != nil else {
            throw CaseFailure(message: "no Core bundle on this host", location: "ResourceLocator")
        }
        func dataset(_ name: String) -> URL? {
            ResourceLocator.coreDatasetDirectory(named: name)
        }
        guard let tz = dataset("NumlexTimezones"), (try? TimezoneCatalog(contentsOf: tz)) != nil else {
            throw CaseFailure(message: "timezone catalog failed through the locator",
                              location: "ResourceLocator")
        }
        guard let hol = dataset("NumlexHolidays"), (try? HolidayCatalog(contentsOf: hol)) != nil else {
            throw CaseFailure(message: "holiday catalog failed through the locator",
                              location: "ResourceLocator")
        }
        guard let inc = dataset("NumlexIncomeTax"), (try? IncomeTaxCatalog(contentsOf: inc)) != nil else {
            throw CaseFailure(message: "income-tax catalog failed through the locator",
                              location: "ResourceLocator")
        }
        guard let cpi = dataset("NumlexCPI"), (try? CPICatalog(contentsOf: cpi)) != nil else {
            throw CaseFailure(message: "CPI catalog failed through the locator",
                              location: "ResourceLocator")
        }
        guard let tax = dataset("NumlexTax"), (try? TaxPresetCatalog(contentsOf: tax)) != nil else {
            throw CaseFailure(message: "tax-preset catalog failed through the locator",
                              location: "ResourceLocator")
        }
        // The production `shared` singletons (the first-launch path that
        // trapped) resolve too.
        try expect(TimezoneCatalog.shared != nil, "TimezoneCatalog.shared loads")
        try expect(HolidayCatalog.shared != nil, "HolidayCatalog.shared loads")
        try expect(IncomeTaxCatalog.shared != nil, "IncomeTaxCatalog.shared loads")
        try expect(CPICatalog.shared != nil, "CPICatalog.shared loads")
        try expect(TaxPresetCatalog.shared != nil, "TaxPresetCatalog.shared loads")
    },

    EngineCase("catalogs-fail-closed-corrupt-copy") {
        // A COPY of the real built bundle (through the production
        // lookup) with one dataset corrupted: the corrupted catalog
        // fails closed (nil), the others still load, and nothing traps.
        guard let real = ResourceLocator.resolveCoreBundle() else {
            return // host without the built bundle: covered by the other cases
        }
        let root = try locatorTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let copy = root.appendingPathComponent(ResourceLocator.coreBundleName)
        try FileManager.default.copyItem(at: real, to: copy)
        // Corrupt the income-tax dataset in the copy only.
        let victim = copy.appendingPathComponent("NumlexIncomeTax/income-tax.json")
        guard FileManager.default.fileExists(atPath: victim.path) else {
            throw CaseFailure(message: "income-tax dataset missing from the built bundle",
                              location: "ResourceLocator")
        }
        let h = try FileHandle(forWritingTo: victim)
        h.seekToEndOfFile()
        h.write(Data("CORRUPT".utf8))
        h.closeFile()
        let corrupted = ResourceLocator.resolveBundle(
            candidates: ResourceLocator.candidateBundleURLs(baseURLs: [root]))
        try expectEqual(corrupted?.standardizedFileURL, copy.standardizedFileURL,
                        "the locator resolves the (corrupt) copy")
        let incDir = ResourceLocator.datasetDirectory(named: "NumlexIncomeTax", in: copy)
        try expect(incDir != nil, "the dataset directory itself still exists")
        try expect((try? IncomeTaxCatalog(contentsOf: incDir!)) == nil,
                   "corrupted integrity => nil (fail closed, no trap)")
        let tzDir = ResourceLocator.datasetDirectory(named: "NumlexTimezones", in: copy)
        try expect(tzDir != nil && (try? TimezoneCatalog(contentsOf: tzDir!)) != nil,
                   "untouched datasets in the same bundle still load")
        // An absent bundle end-to-end: nil everywhere, no crash.
        let emptyBase = root.appendingPathComponent("empty-base")
        try FileManager.default.createDirectory(at: emptyBase, withIntermediateDirectories: true)
        try expect(ResourceLocator.resolveBundle(
            candidates: ResourceLocator.candidateBundleURLs(baseURLs: [emptyBase])) == nil,
            "an empty layout yields nil")
        try expect((try? TimezoneCatalog(contentsOf: emptyBase)) == nil,
                   "loading from an empty directory fails closed")
    },

    // MARK: - source / packaging contracts

    EngineCase("production-core-has-no-bundle-module") {
        let catalogs = [
            "Sources/NumlexCore/Units/TimezoneCatalog.swift",
            "Sources/NumlexCore/Units/HolidayCatalog.swift",
            "Sources/NumlexCore/Units/IncomeTaxCatalog.swift",
            "Sources/NumlexCore/Units/CPICatalog.swift",
            "Sources/NumlexCore/Units/TaxPresetCatalog.swift",
        ]
        for path in catalogs {
            let src = try locatorSource(path)
            try expect(!src.contains("Bundle.module"),
                       "\(path) never touches the generated accessor")
            try expect(!src.contains("#if SWIFT_PACKAGE"),
                       "\(path) has no SwiftPM conditional in the load path")
            try expect(src.contains("ResourceLocator.coreDatasetDirectory"),
                       "\(path) loads through the centralized locator")
        }
        // The locator itself: no generated accessor, no trap, no
        // developer-absolute path, no build-directory literal.
        let locator = try locatorSource("Sources/NumlexCore/Models/ResourceLocator.swift")
        try expect(!locator.contains("Bundle.module"), "locator never touches Bundle.module")
        try expect(!locator.contains("/Users/"), "locator carries no developer path")
        try expect(!locator.contains(".build"), "locator carries no build-directory literal")
        try expect(!locator.contains("fatalError") && !locator.contains("precondition"),
                   "locator never traps")
    },

    EngineCase("packaging-scripts-select-exact-and-standard-locations") {
        let build = try locatorSource("scripts/build-app.sh")
        try expect(build.contains("CORE_BUNDLE=\"$BIN_PATH/Numlex_NumlexCore.bundle\""),
                   "build-app takes the bundle from the EXACT bin path of the requested config")
        try expect(!build.contains("find \"$ROOT/.build\" -maxdepth 3"),
                   "build-app no longer `find`s over .build")
        try expect(build.contains("App root must contain exactly 'Contents'"),
                   "build-app fails closed on any root-level bundle")
        let validate = try locatorSource("scripts/validate-dmg.sh")
        try expect(validate.contains("$APP/Contents/Resources/Numlex_NumlexCore.bundle"),
                   "validate-dmg checks the lookup-compatible STANDARD location")
        try expect(validate.contains("$APP/Numlex_NumlexCore.bundle"),
                   "validate-dmg rejects a root-level bundle inside the app")
        try expect(validate.contains("app root exactly: Contents"),
                   "validate-dmg asserts the self-contained app root")
        let smoke = try locatorSource("Scripts/relocated-app-smoke.sh")
        try expect(smoke.contains("--validate-packaged-resources"),
                   "the relocated smoke uses the opt-in validation flag")
        try expect(smoke.contains("mktemp -d /tmp/numlex-relocated-smoke"),
                   "the smoke copies the app OUTSIDE the repo")
    },

    EngineCase("app-entry-validation-flag-contract") {
        let entry = try locatorSource("Sources/NumlexApp/Entry.swift")
        try expect(entry.contains("@main"), "the explicit entry owns @main")
        try expect(entry.contains("--validate-packaged-resources"), "the smoke flag is parsed")
        try expect(entry.contains("exit(PackagedResourceValidation.run())"),
                   "the flag path exits before the app starts")
        try expect(!entry.contains("NSApplication") && !entry.contains("NSWindow")
            && !entry.contains("Sparkle"),
                   "the flag path opens no window, store, updater or appearance work")
        try expect(entry.contains("NumlexApp.main()"),
                   "normal launches are exactly NumlexApp.main()")
        let app = try locatorSource("Sources/NumlexApp/NumlexApp.swift")
        try expect(!app.contains("@main"), "NumlexApp no longer carries @main")
    },
]
