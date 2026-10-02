import Foundation

/// Pure projection rules for the per-window, session-only Minimal Mode.
/// The normal preferences remain owned by `AppSettings`; these helpers only
/// determine what a particular window should present and persist.
public enum MinimalModePresentation {
    /// The sidebar is never part of the Minimal Mode projection.
    public static func sidebarVisible(isMinimalMode: Bool,
                                      normalSidebarVisible: Bool) -> Bool {
        !isMinimalMode && normalSidebarVisible
    }

    /// Hide only the Floating Total footer in Minimal Mode. Inline total rows
    /// remain ordinary evaluated notebook content.
    public static func showTotalBar(isMinimalMode: Bool,
                                    normalShowTotalBar: Bool) -> Bool {
        !isMinimalMode && normalShowTotalBar
    }

    /// A compact or in-flight frame is not the user's normal launch geometry.
    /// Native full-screen transitions also temporarily own window geometry.
    public static func shouldPersistNormalFrame(isMinimalMode: Bool,
                                                isTransitioning: Bool,
                                                isNativeFullScreen: Bool = false) -> Bool {
        !isMinimalMode && !isTransitioning && !isNativeFullScreen
    }

    /// A queued geometry request may apply only when it is still the latest
    /// request for the window that owns the work.
    public static func isCurrentGeometryRequest(requestGeneration: UInt64,
                                                latestGeneration: UInt64,
                                                ownsWindow: Bool) -> Bool {
        ownsWindow && requestGeneration == latestGeneration
    }
}
