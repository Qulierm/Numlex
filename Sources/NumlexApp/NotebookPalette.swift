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
        numbers = Self.color(for: styling.numbers)
        operators = Self.color(for: styling.operators)
        variables = Self.color(for: styling.variables)
        units = Self.color(for: styling.units)
        specifiers = Self.color(for: styling.specifiers)
        headings = Self.color(for: styling.headings)
        comments = Self.color(for: styling.comments)
        labels = Self.color(for: styling.labels)
    }

    /// The deterministic sRGB swatch for one finite color choice. The
    /// app's established roles map to their EXACT existing palette
    /// values; Standard Text is the fixed white base.
    static func color(for choice: RoleColorChoice) -> NSColor {
        switch choice {
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