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
/// Fonts resolve to the same native face in BOTH renderers: the exact
/// resolved `NSFont` for TextKit/geometry and a fixed-size SwiftUI
/// `Font` built from that font's PostScript name, so the editor, the
/// answer column, token capsule labels and the preview always use the
/// same face, and line-height/baseline math runs on the real font.
///
/// r90: the palette carries the FULL styling selection. `fontDesign`
/// resolves exactly as before when no installed family is selected;
/// `fontFamily`/`fontFace` resolve through the one shared
/// `InstalledFontCatalog`, with the system-design font as the fallback
/// for an unavailable font. Semibold/heavy requests derive their weight
/// inside the selected family.
struct NotebookPalette {
    /// The full styling value this palette was resolved from — the
    /// editor, answers and preview share one instance.
    let styling: StylingPreferences
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
        self.styling = styling
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
        // Package 7: tags use fixed semantic colors; a divider is a
        // calm neutral rule.
        case .tagMarker: Design.tagMarkerColor
        case .tagBody: Design.tagBodyColor
        case .divider: Design.dividerColor
        }
    }

    // MARK: Fonts (same face in TextKit and SwiftUI)

    /// The system-design font for one size/weight — the pre-r90 behavior
    /// and the fallback for an unavailable installed font.
    func systemDesignFont(size: Double, weight: NSFont.Weight = .regular) -> NSFont {
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

    /// The resolved notebook font at one weight: the installed family/face
    /// when one is selected and available, otherwise the built-in design.
    /// For a custom family, a semibold/bold request derives the bold trait
    /// INSIDE that family (the base face when the family has no bold
    /// member) instead of silently jumping to a system face.
    func editorFont(size: Double, weight: NSFont.Weight = .regular) -> NSFont {
        let base = systemDesignFont(size: size, weight: weight)
        guard let family = styling.fontFamily else { return base }
        let resolved = InstalledFontCatalog.shared.font(family: family,
                                                        face: styling.fontFace,
                                                        size: size,
                                                        fallback: base)
        switch weight {
        case .semibold, .bold, .heavy, .black:
            return InstalledFontCatalog.boldVariant(of: resolved)
        default:
            return resolved
        }
    }

    /// The semibold companion of the resolved regular font: the bold
    /// trait derived inside the selected family (headings and subtotal
    /// rows), or the same system-design semibold as before when no
    /// installed family is selected.
    func semiboldFont(size: Double) -> NSFont {
        guard styling.fontFamily != nil else {
            return systemDesignFont(size: size, weight: .semibold)
        }
        return InstalledFontCatalog.boldVariant(of: editorFont(size: size))
    }

    /// The heavy companion of the resolved regular font (total rows).
    func heavyFont(size: Double) -> NSFont {
        guard styling.fontFamily != nil else {
            return systemDesignFont(size: size, weight: .heavy)
        }
        return InstalledFontCatalog.heavyVariant(of: editorFont(size: size))
    }

    /// The SwiftUI side of one already-resolved font: a FIXED-SIZE custom
    /// font built from the exact PostScript name, so SwiftUI renders the
    /// same face TextKit measures (never a re-resolved design that could
    /// drift).
    static func swiftUIFont(_ font: NSFont, size: Double) -> Font {
        Font.custom(font.fontName, fixedSize: size)
    }

    func swiftUIFont(_ size: Double, weight: Font.Weight = .regular) -> Font {
        switch weight {
        case .semibold, .bold:
            return Self.swiftUIFont(semiboldFont(size: size), size: size)
        case .heavy, .black:
            return Self.swiftUIFont(heavyFont(size: size), size: size)
        default:
            return Self.swiftUIFont(editorFont(size: size), size: size)
        }
    }

    /// r90: the effective notebook line height. The requested line height
    /// (the legacy `fontSize * 1.6`) stays the FLOOR, so system-font
    /// geometry is unchanged; an installed font with taller natural
    /// metrics raises it to `ceil(max natural height of the regular,
    /// semibold and heavy faces + 4 pt)` so glyphs can never clip.
    func effectiveLineHeight(requested: Double, fontSize: Double) -> Double {
        guard styling.fontFamily != nil else { return requested }
        let faces = [editorFont(size: fontSize),
                     semiboldFont(size: fontSize),
                     heavyFont(size: fontSize)]
        let tallest = faces.reduce(0.0) { partial, font in
            max(partial, Double(font.ascender - font.descender + font.leading))
        }
        return max(requested, (tallest + 4).rounded(.up))
    }

    /// The line height the app should use for one styling value — the ONE
    /// call site shape shared by the editor, the answer column and the
    /// settings preview.
    static func effectiveLineHeight(styling: StylingPreferences,
                                    requested: Double,
                                    fontSize: Double) -> Double {
        NotebookPalette(styling: styling)
            .effectiveLineHeight(requested: requested, fontSize: fontSize)
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