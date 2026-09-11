import AppKit
import NumlexCore

/// Locates the bundled icon resources without ever touching
/// `Bundle.module`.
///
/// `Bundle.module`'s generated accessor calls `fatalError` when the
/// SwiftPM resource bundle is absent — which is exactly the situation in
/// a packaged `.app` assembled by `Scripts/build-app.sh` (the resources
/// live in `Contents/Resources`, not in a SwiftPM bundle). The loader
/// therefore checks `Bundle.main` FIRST (packaged app and release builds)
/// and only then the development resource bundle sitting next to the
/// executable produced by `swift run`/`swift build`.
enum AppIconResources {
    /// The SwiftPM resource bundle for the app target, if present.
    static func developmentBundle() -> Bundle? {
        let fm = FileManager.default
        var candidates: [URL] = []
        // Next to the executable: .build/<config>/Numlex_NumlexApp.bundle
        candidates.append(Bundle.main.bundleURL
            .appendingPathComponent("Numlex_NumlexApp.bundle"))
        // Inside a test runner bundle or a differently staged build dir.
        candidates.append(Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("Numlex_NumlexApp.bundle"))
        for url in candidates where fm.fileExists(atPath: url.path) {
            if let bundle = Bundle(url: url) { return bundle }
        }
        return nil
    }

    /// The resource URL for a packaged-or-development resource, or nil
    /// when it is missing (callers fail safe — never a crash).
    static func url(forResource name: String, withExtension ext: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }
        return developmentBundle()?.url(forResource: name, withExtension: ext)
    }

    /// The alternate Light application icon (the exact committed ICNS).
    static func lightIconImage() -> NSImage? {
        guard let url = url(forResource: "AppIconLight", withExtension: "icns") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    /// The Settings preview tile for a choice: the two supplied PNGs,
    /// decoded from the packaged bytes — never generated from a display
    /// string or rasterized at runtime.
    static func previewImage(for choice: AppIconChoice) -> NSImage? {
        let name = (choice == .dark) ? "AppIconDarkPreview" : "AppIconLightPreview"
        guard let url = url(forResource: name, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }
}

/// THE one application-icon mechanism.
///
/// The persisted `AppSettings.appIcon` (in the store) is the single
/// source of truth — there is no duplicate UserDefaults key and no
/// alternate-icon machinery. This type is the only code that writes
/// `NSApp.applicationIconImage`: once at launch (before the first visible
/// frame, via AppDelegate) and again on every user change (through
/// `AppModel.setAppIcon`).
///
/// Scope: the Dock and the App Switcher. The Finder icon of the
/// installed bundle is the SIGNED bundle's icon and is never touched —
/// no `NSWorkspace.setIcon`, no Finder metadata, no bundle mutation, so
/// permissions, the code signature and update trust stay intact.
///
/// `.light` applies the exact packaged alternate ICNS. `.dark` restores
/// the bundle default through AppKit's null-resettable contract
/// (`applicationIconImage = nil` → the current primary bundle icon,
/// including the modern `Assets.car` rendition). Should a host fail to
/// take the null reset, the controller falls back to the icon image
/// AppKit itself resolved at launch — never a hand-rasterized
/// substitute.
@MainActor
enum AppIconController {
    /// The last value this controller applied to the process.
    private static var applied: AppIconChoice?
    /// The icon image AppKit resolved from the bundle at launch (may be
    /// nil, which is itself the bundle default).
    private static var launchIcon: NSImage?
    private static var didCaptureLaunchIcon = false

    /// Captures the bundle-resolved icon ONCE, before any user choice is
    /// applied. Safe to call repeatedly.
    static func captureLaunchIcon() {
        guard !didCaptureLaunchIcon, let app = NSApp else { return }
        launchIcon = app.applicationIconImage
        didCaptureLaunchIcon = true
    }

    /// Applies the choice process-wide (idempotent). Returns true when
    /// the process icon now matches the requested choice.
    @discardableResult
    static func apply(_ choice: AppIconChoice) -> Bool {
        guard let app = NSApp else { return false }  // never from App.init
        guard choice != applied else { return true }
        switch choice {
        case .dark:
            restoreBundleDefault(app)
            applied = .dark
            return true
        case .light:
            // A missing/corrupt resource fails safe: keep whatever icon
            // is showing and DO NOT pretend the choice was applied.
            guard let image = AppIconResources.lightIconImage() else { return false }
            app.applicationIconImage = image
            applied = .light
            return true
        }
    }

    /// The authoritative persisted choice at launch: the store's settings
    /// (missing key / invalid value / unreadable store all decode to the
    /// default `.dark`, the modern bundle primary).
    static func persistedChoice() -> AppIconChoice {
        Persistence.load()?.settings.appIcon ?? .dark
    }

    /// AppKit's null-resettable bundle default, with the documented
    /// fallback for a host where the null reset does not take effect.
    private static func restoreBundleDefault(_ app: NSApplication) {
        app.applicationIconImage = nil
        if let launchIcon, !iconsMatch(app.applicationIconImage, launchIcon) {
            app.applicationIconImage = launchIcon
        }
    }

    /// Whether two icon images are the same rendered glyph — compared
    /// through their PNG representations (stable for the same
    /// `NSImage`/bundle icon), with nil meaning "the bundle default".
    static func iconsMatch(_ a: NSImage?, _ b: NSImage?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case (nil, _), (_, nil): return false
        case (let x?, let y?):
            if x === y { return true }
            return pngData(x) == pngData(y)
        }
    }

    private static func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Test-only view of the launch capture (never used in production
    /// decisions beyond the documented fallback above).
    static var capturedLaunchIcon: NSImage? { launchIcon }
    static var lastApplied: AppIconChoice? { applied }
}
