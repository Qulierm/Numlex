import Foundation

/// Central, safe resource locator for the offline catalog datasets
/// (`NumlexTimezones`, `NumlexHolidays`, `NumlexIncomeTax`, `NumlexCPI`,
/// `NumlexTax`).
///
/// WHY THIS EXISTS (the 4.9.2 first-launch crash): SwiftPM generates a
/// resource accessor for the NumlexCore resources whose two candidates
/// are (a) `Bundle.main.bundleURL/<bundle>` — which misses the STANDARD
/// packaged location, because a `.app` keeps resources under
/// `Contents/Resources` (i.e. `Bundle.main.resourceURL`, not
/// `bundleURL`) — and (b) an ABSOLUTE build path recorded on the
/// DEVELOPER machine. In a packaged app installed anywhere else both
/// candidates miss and the generated accessor traps the process on
/// first launch the moment the first catalog
/// (IncomeTaxCatalog via FinancialContext after Get Started) initializes.
///
/// This locator replaces that accessor everywhere in production:
/// it NEVER touches the generated accessor, NEVER contains a
/// developer-absolute path, and NEVER traps — a missing or corrupt
/// resource is `nil` (or a typed catalog load error), full stop.
///
/// Lookup order (the first existing DIRECTORY wins):
///   1. `Bundle.main.resourceURL/<bundle>` — the standard packaged
///      location (`Numlex.app/Contents/Resources/Numlex_NumlexCore.bundle`);
///   2. `Bundle.main.bundleURL/<bundle>` — the SwiftPM layout, where the
///      generated bundle sits next to the executable / test runner;
///   3. `Bundle.main.bundleURL/Contents/MacOS/<bundle>` — a binary with
///      the bundle as a sibling inside a bare `.app`-shaped directory
///      (for a bare executable, step 2 already covers the executable
///      directory, which is `bundleURL`);
///   4. the current working directory — `swift run` / test invocations
///      from the repository root (derived at runtime; never a literal).
///
/// Candidate generation and resolution are PURE functions of the
/// injected base URLs, so the packaged, SwiftPM-root, sibling, and
/// direct layouts are testable with temporary directories and no
/// process globals.
public enum ResourceLocator {
    /// The name of the SwiftPM-generated bundle carrying the NumlexCore
    /// resources.
    public static let coreBundleName = "Numlex_NumlexCore.bundle"

    // MARK: pure candidate generation / resolution

    /// Pure candidate generation: for every base URL (in order) the
    /// `<base>/<coreBundleName>` location, then the optional
    /// `directBundleURL` (a plain bundle/directory layout that is not
    /// under any base, used by direct-resource test/dev layouts).
    /// Candidates are deduplicated by their standardized,
    /// symlink-resolved path; the input order is preserved.
    public static func candidateBundleURLs(
        baseURLs: [URL?],
        directBundleURL: URL? = nil
    ) -> [URL] {
        var seen = Set<URL>()
        var out: [URL] = []
        func add(_ url: URL?) {
            guard let url else { return }
            let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
            guard seen.insert(canonical).inserted else { return }
            out.append(canonical)
        }
        for base in baseURLs {
            add(base?.appendingPathComponent(coreBundleName))
        }
        add(directBundleURL)
        return out
    }

    /// The first candidate that exists as a directory (a resource
    /// "bundle" is just a directory of datasets). Missing paths and
    /// plain-file candidates are skipped. `nil` when none qualify —
    /// callers fail closed; this never traps.
    public static func resolveBundle(
        candidates: [URL],
        fileManager: FileManager = .default
    ) -> URL? {
        var isDirectory = ObjCBool(false)
        for url in candidates {
            isDirectory = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else { continue }
            return url
        }
        return nil
    }

    /// The dataset directory (`NumlexTimezones`, ...) inside a resolved
    /// bundle, or `nil` when it is absent or is not a directory.
    public static func datasetDirectory(
        named name: String,
        in bundleURL: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        let url = bundleURL.appendingPathComponent(name)
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return nil }
        return url
    }

    // MARK: production convenience (process bases)

    /// The ordered, deduplicated base URLs for THIS process, in the
    /// documented lookup order. Pure with respect to the injected
    /// `mainBundle`/`fileManager`, so tests can pass fakes.
    public static func processBaseURLs(
        mainBundle: Bundle = .main,
        fileManager: FileManager = .default
    ) -> [URL] {
        var seen = Set<URL>()
        var out: [URL] = []
        func add(_ url: URL?) {
            guard let url else { return }
            let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
            guard seen.insert(canonical).inserted else { return }
            out.append(canonical)
        }
        add(mainBundle.resourceURL)
        add(mainBundle.bundleURL)
        add(mainBundle.bundleURL.appendingPathComponent("Contents/MacOS"))
        add(URL(fileURLWithPath: fileManager.currentDirectoryPath))
        return out
    }

    /// Production resolution: the NumlexCore bundle for this process
    /// through the full ordered lookup, or `nil` (never a trap) when no
    /// layout applies.
    public static func resolveCoreBundle(
        mainBundle: Bundle = .main,
        fileManager: FileManager = .default
    ) -> URL? {
        resolveBundle(
            candidates: candidateBundleURLs(
                baseURLs: processBaseURLs(mainBundle: mainBundle, fileManager: fileManager)),
            fileManager: fileManager
        )
    }

    /// Production resolution: a dataset directory for this process, or
    /// `nil` when the bundle or the dataset is missing.
    public static func coreDatasetDirectory(
        named name: String,
        mainBundle: Bundle = .main,
        fileManager: FileManager = .default
    ) -> URL? {
        guard let bundle = resolveCoreBundle(mainBundle: mainBundle, fileManager: fileManager)
        else { return nil }
        return datasetDirectory(named: name, in: bundle, fileManager: fileManager)
    }
}
