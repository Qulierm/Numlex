import AppKit
import NumlexCore

/// r38: THE one application-appearance mechanism.
///
/// The persisted `AppSettings.appearance` (in the store) is the single
/// source of truth — there is no duplicate UserDefaults theme key.
/// This type is the only code that writes `NSApp.appearance`: once at
/// launch (the authoritative persisted value, before the first visible
/// frame) and again on every user change (via `AppModel.setAppearance`),
/// so AppKit windows, title bars and tab chrome, native menus, context
/// menus, popovers, file panels and every Liquid Glass surface follow
/// the choice process-wide — not just SwiftUI content.
///
/// Application is idempotent: a repeated value is a no-op (no
/// feedback/persist loop), and a call before `NSApp` exists (App.init
/// territory — that crashed the app in r36) is silently dropped.
///
/// `NSApp` is main-thread state, so the controller is main-actor
/// isolated; every caller (the delegate hook, the model init and the
/// settings change path) already runs on the main actor.
@MainActor
enum AppAppearanceController {
    /// The two pinned process appearances (stable instances, so repeat
    /// applications never manufacture a spurious change).
    private static let aqua = NSAppearance(named: .aqua)!
    private static let darkAqua = NSAppearance(named: .darkAqua)!

    /// The last value this controller applied to the process.
    private static var applied: AppAppearance?

    /// Applies the choice process-wide (idempotent).
    static func apply(_ appearance: AppAppearance) {
        guard let app = NSApp else { return } // never from App.init
        guard appearance != applied else { return }
        app.appearance = (appearance == .light) ? aqua : darkAqua
        applied = appearance
    }

    /// The authoritative persisted choice at launch: the store's
    /// settings (missing key / invalid value / unreadable store all
    /// decode to `.light` — the r36 behavior).
    static func persistedAppearance() -> AppAppearance {
        Persistence.load()?.settings.appearance ?? .light
    }
}
