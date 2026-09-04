import Foundation

/// r52: deterministic adaptive tones for the sidebar glass surfaces
/// (New Sheet button, selected sheet row, active folder tab, sheet
/// drop highlight). Pure Foundation so the token semantics are unit
/// tested without pixel assumptions; the app target (Design.swift)
/// bridges these values into a dynamic NSColor that re-resolves
/// through the effective pinned appearance on every Light/Dark switch.
public struct GlassTone: Equatable, Sendable {
    /// sRGB channel in 0...1.
    public let red: Double
    public let green: Double
    public let blue: Double
    /// Fill/stroke alpha in 0...1.
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Perceptual luminance (0...1): sRGB-linearized channels with the
    /// Rec. 709 weights. "Darker than white" means luminance < 1.
    public var luminance: Double {
        func linearize(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(red)
             + 0.7152 * linearize(green)
             + 0.0722 * linearize(blue)
    }
}

public enum SidebarGlassTone {
    /// Which glass role the caller wants.
    public enum Role: Sendable {
        /// New Sheet button, selected sheet row, active folder tab.
        case selected
        /// A row/tab highlighted as a sheet drop target.
        case dropTarget
    }

    /// Surface tint for the role under the given appearance.
    public static func tint(_ role: Role, isDark: Bool) -> GlassTone {
        switch (role, isDark) {
        case (.selected, true):
            // Dark: the historical white 10% glass — unchanged.
            return GlassTone(red: 1, green: 1, blue: 1, alpha: 0.10)
        case (.selected, false):
            // Light: subtle neutral graphite 4% over the white
            // sidebar — visible without looking dirty or heavy.
            return GlassTone(red: 0, green: 0, blue: 0, alpha: 0.04)
        case (.dropTarget, true):
            // Dark: the historical white 22% glass — unchanged.
            return GlassTone(red: 1, green: 1, blue: 1, alpha: 0.22)
        case (.dropTarget, false):
            // Light: calm accent-aware blue (the Design.caretColor
            // #3478F7 accent) at 12% — distinctly stronger than the
            // 4% selected tint while staying quiet.
            return GlassTone(red: 52.0 / 255.0, green: 120.0 / 255.0,
                             blue: 247.0 / 255.0, alpha: 0.12)
        }
    }

    /// Hairline boundary drawn over the glass (1 pt, hit-testing off).
    /// Light only: macOS 26 Liquid Glass understates a 4% tint against
    /// pure white, so the pill needs a subtle 10% dark boundary. Dark
    /// keeps the self-evident white glass — clear boundary.
    public static func boundary(isDark: Bool) -> GlassTone {
        isDark
            ? GlassTone(red: 0, green: 0, blue: 0, alpha: 0)
            : GlassTone(red: 0, green: 0, blue: 0, alpha: 0.10)
    }
}
