import Foundation
import NumlexCore

/// Process entry point: the ONE place that decides whether the app even
/// starts.
///
/// Opt-in smoke flag `--validate-packaged-resources`: runs
/// `PackagedResourceValidation` and exits BEFORE any window, store,
/// updater, or appearance work — so a COPIED (relocated)
/// packaged binary can prove its offline catalog bundle resolves and all
/// five catalogs load through the production path, with no GUI. Inert in
/// normal launches: without the flag the behavior is exactly
/// `NumlexApp.main()`.
@main
enum NumlexEntry {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--validate-packaged-resources") {
            exit(PackagedResourceValidation.run())
        }
        NumlexApp.main()
    }
}

/// Deterministic packaged-resource smoke check (opt-in, see
/// `NumlexEntry`). Resolves the offline catalog bundle through the
/// production `ResourceLocator` — which contains no developer build-path
/// literal, so a copied app can only be satisfied by ITS OWN
/// `Contents/Resources` — then loads all five catalogs through the
/// production `embedded()` path, printing one status line each.
///
/// Exits 0 only when the bundle resolves AND all five catalogs load: a
/// packaged release must carry them all (the build fails closed on any
/// omission). A missing bundle or dataset is reported and exits nonzero
/// — it is NEVER a trap. Never opens a window, store, or updater.
enum PackagedResourceValidation {
    /// The five offline datasets, in packaging order. Computed (not a
    /// stored global) so the flag path stays concurrency-clean.
    static var datasets: [(name: String, load: () -> Bool)] {
        [
            ("NumlexTimezones", { TimezoneCatalog.embedded() != nil }),
            ("NumlexHolidays", { HolidayCatalog.embedded() != nil }),
            ("NumlexIncomeTax", { IncomeTaxCatalog.embedded() != nil }),
            ("NumlexCPI", { CPICatalog.embedded() != nil }),
            ("NumlexTax", { TaxPresetCatalog.embedded() != nil }),
        ]
    }

    @discardableResult
    static func run() -> Int32 {
        guard let bundle = ResourceLocator.resolveCoreBundle() else {
            print("packaged-resources: FAIL bundle not found (no layout in the lookup order applies)")
            return 1
        }
        print("packaged-resources: bundle \(bundle.path)")
        var failures = 0
        for entry in datasets {
            let present = ResourceLocator.datasetDirectory(named: entry.name, in: bundle) != nil
            if entry.load() {
                print("packaged-resources: ok \(entry.name)")
            } else {
                print("packaged-resources: FAIL \(entry.name) (dataset directory present: \(present))")
                failures += 1
            }
        }
        return failures == 0 ? 0 : 1
    }
}
