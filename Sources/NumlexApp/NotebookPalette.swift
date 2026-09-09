import AppKit
import SwiftUI
import NumlexCore

/// r21: THE single palette/typography resolver for notebook text.
///
/// Both the real editor (TextKit) and the settings preview (SwiftUI)
/// resolve every configurable role through this type — the sRGB channel
/// values live in exactly one place (the existing `Design` tokens for
/// the app's established roles; the fixed base is `Design.baseText`),
/// so no divergent RGB copy can drift in. The non-configurable palette
/// pieces (money markers, answer tokens, caret, headings marker) stay
/// hardcoded `Design` tokens.
///
/// Fonts resolve to the same native system design in BOTH renderers:
/// `NSFont.systemFont(ofSize:weight:design:)` for TextKit/geometry and
/// `Font.system(size:weight:design:)` for SwiftUI, so the editor, the
/// answer column, token capsule labels and the preview always use the
/// same face, and line-height/baseline math runs on the real font.
struct NotebookPalette {
    let fontDesign: StylingFontDesign
    let numbers: NSColor
    let operators: NSColor
    let variables: NSColor
    let units: NSColor
    let specifiers: NSColor
    let headings: NSColor
    let comments: NSColor
    let labels: NSColor

    init(styling: StylingPreferences) {
        fontDesign = styling.fontDesign
        // r89: every role resolves `custom ?? preset` through the ONE
        // sRGB conversion below; the editor (TextKit) and the settings
        // preview consume this exact instance, so no RGB value is
        // resolved twice.
        numbers = Self.color(for: styling.numbers,
                             custom: styling.customColor(for: .numbers))
        operators = Self.color(for: styling.operators,
                               custom: styling.customColor(for: .operators))
        variables = Self.color(for: styling.variables,
                               custom: styling.customColor(for: .variables))
        units = Self.color(for: styling.units,
                           custom: styling.customColor(for: .units))
        specifiers = Self.color(for: styling.specifiers,
                                custom: styling.customColor(for: .specifiers))
        headings = Self.color(for: styling.headings,
                              custom: styling.customColor(for: .headings))
        comments = Self.color(for: styling.comments,
                              custom: styling.customColor(for: .comments))
        labels = Self.color(for: styling.labels,
                            custom: styling.customColor(for: .labels))
    }

    /// r89: the effective swatch for one role — the custom opaque sRGB
    /// override when present (exact in Light and Dark alike),
    /// otherwise the role's preset. The custom branch is the ONE exact
    /// sRGB conversion the whole app uses; the preset branch keeps the
    /// established (possibly adaptive) Design tokens.
    static func color(for choice: RoleColorChoice,
                      custom: SyntaxSRGBColor? = nil) -> NSColor {
        if let custom {
            return NSColor(srgbRed: Double(custom.r) / 255,
                           green: Double(custom.g) / 255,
                           blue: Double(custom.b) / 255, alpha: 1)
        }
        return switch choice {
        case .standardText: Design.baseText
        case .cyan: Design.numberColor
        case .green: Design.variableColor
        case .pinkPurple: Design.conversionColor
        case .blue: Design.titleColor
        case .moneyPurple: Design.moneyMarkerColor
        }
    }

    /// The role color that owns one syntax role (used by the editor's
    /// span painter and the preview alike).
    func color(forRole role: SyntaxRole) -> NSColor? {
        switch role {
        case .number: numbers
        case .operatorGlyph: operators
        case .variable: variables
        case .conversion: units
        case .specifier: specifiers
        case .label: labels
        // Money markers, hash marker/body and tokens are fixed design
        // tokens, never user-configurable.
        case .moneyMarker: Design.moneyMarkerColor
        case .hashMarker: Design.headingMarkerColor
        case .hashBody: headings
        }
    }

    // MARK: Fonts (same design in TextKit and SwiftUI)

    func editorFont(size: Double, weight: NSFont.Weight = .regular) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        let design: NSFontDescriptor.SystemDesign
        switch fontDesign {
        case .system: return base
        case .rounded: design = .rounded
        case .serif: design = .serif
        case .monospaced: design = .monospaced
        }
        // Descriptor round-trip keeps the exact weight/size and swaps the
        // system design (verified: .AppleSystemUIFontRounded/NewYork/
        // Monospaced variants); a failed swap falls back to the base font
        // rather than crashing the editor.
        if let descriptor = base.fontDescriptor.withDesign(design),
           let designed = NSFont(descriptor: descriptor, size: size) {
            return designed
        }
        return base
    }

    func swiftUIFont(_ size: Double, weight: Font.Weight = .regular) -> Font {
        Font.system(size: size, weight: weight, design: swiftUIFontDesign)
    }

    private var swiftUIFontDesign: Font.Design {
        switch fontDesign {
        case .system: .default
        case .rounded: .rounded
        case .serif: .serif
        case .monospaced: .monospaced
        }
    }
}

// MARK: - r89: canonical <-> platform color mechanics (app-side only)

extension SyntaxSRGBColor {
    /// The ONE AppKit conversion of the canonical triple: an opaque
    /// sRGB NSColor with exact components (the settings swatches, the
    /// preview and the editor all draw from it).
    var nsColor: NSColor {
        NSColor(srgbRed: Double(r) / 255, green: Double(g) / 255,
                blue: Double(b) / 255, alpha: 1)
    }

    /// The SwiftUI side of the same conversion (ColorPickers, swatches).
    var color: Color { Color(nsColor: nsColor) }

    /// Quantizes an arbitrary platform color (any color space — the
    /// conversion is AppKit-only) to the canonical opaque sRGB triple.
    /// Returns `nil` when the color cannot be converted at all.
    init?(_ color: Color) {
        let converted = NSColor(color).usingColorSpace(.sRGB)
        guard let converted else { return nil }
        self.init(converted.redComponent,
                converted.greenComponent,
                converted.blueComponent)
    }
}