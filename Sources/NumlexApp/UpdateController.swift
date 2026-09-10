import Foundation
import AppKit
import Sparkle
import NumlexCore

/// The app's ONE Sparkle integration layer (Swift 6, main-actor isolated).
///
/// Responsibilities:
///   - read and validate the packaged updater metadata
///     (`UpdateConfiguration` in NumlexCore, unit-tested);
///   - own the single `SPUStandardUpdaterController` (official Sparkle API,
///     Sparkle's own UI only — no custom updater window);
///   - publish `canCheckForUpdates` / `automaticallyChecksForUpdates` for the
///     menu item and the Settings UI;
///   - disable itself gracefully (no crash, no updater started) when the
///     required packaged metadata is unavailable — for example
///     `swift run Numlex`, a bare executable with no `.app` Info.plist.
///
/// Ownership rule: `automaticallyChecksForUpdates` belongs to Sparkle's own
/// `UserDefaults` (bundle domain). It is never mirrored into `AppSettings`,
/// the JSON store or `.nlx`.
@MainActor
@Observable
final class UpdateController {
    /// The validated packaged configuration (missing keys become nil).
    let configuration: UpdateConfiguration
    /// Non-nil when the updater is deliberately disabled.
    private(set) var unavailableReason: UpdateUnavailableReason?
    /// Sparkle's own availability flag for a user-initiated check.
    private(set) var canCheckForUpdates = false
    /// Sparkle's own persisted automatic-check preference.
    private(set) var automaticallyChecksForUpdates = false

    /// The live controller; nil when disabled (never a half-built updater).
    private var controller: SPUStandardUpdaterController?
    private var canCheckObservation: NSKeyValueObservation?
    private var automaticObservation: NSKeyValueObservation?

    /// True when the official updater is running for this process.
    var isAvailable: Bool { controller != nil }

    init(bundle: Bundle = .main) {
        let configuration = UpdateConfiguration.from(bundle: bundle)
        self.configuration = configuration

        guard UpdateConfiguration.isPackagedApp(bundle: bundle) else {
            self.unavailableReason = .notPackaged
            return
        }
        if let reason = configuration.unavailableReason {
            self.unavailableReason = reason
            return
        }

        // Official standard controller: it starts the updater, schedules
        // checks with Sparkle's own defaults (24 h, consent on the second
        // launch) and drives Sparkle's standard alert/install/relaunch UI.
        let controller = SPUStandardUpdaterController(startingUpdater: true,
                                                     updaterDelegate: nil,
                                                     userDriverDelegate: nil)
        self.controller = controller
        let updater = controller.updater

        // KVO is the API Sparkle documents for `canCheckForUpdates`; hop to
        // the main actor because the observation fires on the observed thread.
        canCheckObservation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
            let value = change.newValue ?? false
            Task { @MainActor [weak self] in self?.canCheckForUpdates = value }
        }
        automaticObservation = updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] _, change in
            let value = change.newValue ?? false
            Task { @MainActor [weak self] in self?.automaticallyChecksForUpdates = value }
        }
    }

    /// Manual "Check for Updates…". No-op when disabled.
    func checkForUpdates() {
        guard let controller else { return }
        controller.checkForUpdates(nil)
    }

    /// True when the automatic-check switch can be offered.
    var canToggleAutomaticChecks: Bool { controller != nil }

    /// Sparkle-backed automatic-check preference (its own UserDefaults).
    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
        automaticallyChecksForUpdates = controller?.updater.automaticallyChecksForUpdates ?? enabled
    }
}
