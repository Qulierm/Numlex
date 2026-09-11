import Foundation

/// r52: deterministic adaptive washes for the sidebar glass surfaces
/// (New Sheet button, selected sheet row, active folder tab, sheet
/// drop highlight). Pure Foundation so the token semantics are unit
/// tested without pixel assumptions.
///
/// These values are **normal compositing fills**, not glass tints: the
/// app draws the wash as a plain shape fill *underneath* one real,
/// UNTINTED Liquid Glass surface. Alpha is therefore composited by the
/// ordinary fill path (`base·(1−α) + color·α`), which every macOS
/// renderer evaluates identically. Passing an alpha-bearing color into
/// `Glass.tint` is what regressed on macOS 26/27: the new renderer
/// interpreted the alpha as tint *strength*, turning a 4% graphite wash
/// into a near-solid ~62% gray (measured RGB ≈ 96 on the reporter's
/// machine) while other surfaces kept a different resolution.
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

    /// The deterministic sRGB composite of this wash over `base` — the
    /// exact value the normal fill path produces (no glass involved).
    /// Used by the tests to pin "Light stays light" and "Dark stays calm".
    public func composited(over base: GlassTone) -> GlassTone {
        GlassTone(red: base.red * (1 - alpha) + red * alpha,
                  green: base.green * (1 - alpha) + green * alpha,
                  blue: base.blue * (1 - alpha) + blue * alpha,
                  alpha: 1)
    }

    /// Convenience: this wash composited over a grayscale base value.
    public func composited(overGray v: Double) -> GlassTone {
        composited(over: GlassTone(red: v, green: v, blue: v, alpha: 1))
    }
}

public enum SidebarGlassTone {
    /// Which surface role the caller wants.
    public enum Role: Sendable {
        /// New Sheet button, selected sheet row, active folder tab.
        case selected
        /// A row/tab highlighted as a sheet drop target.
        case dropTarget
    }

    /// The wash for the role under the given appearance. Drawn as a
    /// normal fill under one untinted glass surface; never passed to
    /// `Glass.tint`.
    public static func wash(_ role: Role, isDark: Bool) -> GlassTone {
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
            // 4% selected wash while staying quiet.
            return GlassTone(red: 52.0 / 255.0, green: 120.0 / 255.0,
                             blue: 247.0 / 255.0, alpha: 0.12)
        }
    }

    /// Hairline boundary drawn over the glass (1 pt, hit-testing off).
    /// Light only: a 4% wash is understated against pure white, so the
    /// pill needs a subtle 10% dark boundary. Dark keeps the
    /// self-evident white glass — clear boundary.
    public static func boundary(isDark: Bool) -> GlassTone {
        isDark
            ? GlassTone(red: 0, green: 0, blue: 0, alpha: 0)
            : GlassTone(red: 0, green: 0, blue: 0, alpha: 0.10)
    }

    /// The reference white background the Light sidebar sits on, and the
    /// reference dark base, for deterministic composite assertions.
    public static let lightSidebarBase = GlassTone(red: 1, green: 1, blue: 1, alpha: 1)
    public static let darkSidebarBase = GlassTone(red: 0.12, green: 0.12, blue: 0.12, alpha: 1)
}
