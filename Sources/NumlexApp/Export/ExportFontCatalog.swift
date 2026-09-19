import AppKit
import CoreText
import NumlexCore
import SwiftUI

/// r90: the export dialog's font resolution. It no longer enumerates
/// fonts itself — family/face enumeration, the deterministic regular
/// preference and resolution all come from the ONE shared
/// `InstalledFontCatalog`, so the export menus and the notebook
/// typography settings can never disagree. Only font FAMILIES the system
/// reports as installed are offered; resolution has a safe fallback at
/// every step (missing family/face -> the app's notebook font, never a
/// crash and never a silently different face).
struct ExportFontCatalog {
    typealias Face = InstalledFontCatalog.Face

    /// Every installed family, sorted for a stable menu (the shared
    /// catalog's order).
    let families: [String]

    static let shared = ExportFontCatalog(
        families: InstalledFontCatalog.shared.families)

    /// The faces of one family (empty for nil / an unknown family).
    func faces(for family: String?) -> [Face] {
        InstalledFontCatalog.shared.faces(for: family)
    }

    /// Resolves one export face. `family == nil` = the app's notebook
    /// font — which now naturally INHERITS the persisted custom notebook
    /// family/face through `NotebookPalette`. A missing family falls back
    /// to it too. A missing or foreign face falls back to the family's
    /// deterministic regular face.
    func resolve(family: String?, face: String?, size: Double,
                 styling: StylingPreferences) -> NSFont {
        let notebook = NotebookPalette(styling: styling).editorFont(size: size)
        guard let family, families.contains(family) else { return notebook }
        return InstalledFontCatalog.shared.font(family: family, face: face,
                                                size: size, fallback: notebook)
    }

    /// The bridge used by the Core renderer. `NSFontDescriptor` and
    /// `CTFontDescriptor` are toll-free bridged, so the exact face and
    /// design survive the conversion.
    static func coreFont(_ font: NSFont) -> CTFont {
        CTFontCreateWithFontDescriptor(font.fontDescriptor as CTFontDescriptor,
                                       font.pointSize, nil)
    }

    /// The resolved font set for one export: body/answer/heading/title/
    /// chrome/token. Bold variants are derived from the resolved face
    /// through the font manager (never a different family), with a safe
    /// fallback to the base face.
    static func fonts(options: ExportOptions,
                      styling: StylingPreferences,
                      catalog: ExportFontCatalog = .shared) -> ExportFonts {
        let size = options.fontPointSize
        let base = catalog.resolve(family: options.fontFamily,
                                   face: options.fontFace,
                                   size: size, styling: styling)
        let bold = NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
        let token = Design.tokenFont(size: size)
        let chromeSize = max(size * 0.62, 8)
        return ExportFonts(
            expression: coreFont(base),
            answer: coreFont(base),
            semiboldAnswer: coreFont(bold),
            heading: coreFont(bold),
            title: coreFont(NSFont.systemFont(ofSize: size * 0.8, weight: .semibold)),
            chrome: coreFont(NSFont.systemFont(ofSize: chromeSize, weight: .regular)),
            token: coreFont(token))
    }
}

extension ExportPalette {
    /// The print palette: white pages, so every adaptive role is
    /// resolved against the LIGHT appearance; user-chosen custom colors
    /// keep their exact canonical sRGB channels (they are explicit
    /// opaque values and print readably on white).
    @MainActor
    static func printPalette(styling: StylingPreferences) -> ExportPalette {
        func color(_ ns: NSColor) -> ExportColor {
            guard let c = ns.usingColorSpace(.sRGB) else {
                return ExportColor(red: 0, green: 0, blue: 0)
            }
            return ExportColor(red: Double(c.redComponent),
                               green: Double(c.greenComponent),
                               blue: Double(c.blueComponent),
                               alpha: 1)
        }
        var palette = ExportPalette()
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
            let roles = NotebookPalette(styling: styling)
            palette.baseText = color(Design.baseText)
            palette.number = color(roles.numbers)
            palette.operatorGlyph = color(roles.operators)
            palette.variable = color(roles.variables)
            palette.conversion = color(roles.units)
            palette.specifier = color(roles.specifiers)
            palette.label = color(roles.labels)
            palette.moneyMarker = color(Design.moneyMarkerColor)
            palette.headingMarker = color(Design.headingMarkerColor)
            palette.headingBody = color(roles.headings)
            palette.comment = color(roles.comments)
            palette.tokenFill = color(Design.tokenBase)
            palette.tokenFillInactive = color(Design.tokenFillInactive)
            palette.tokenText = color(Design.tokenText)
            palette.tokenTextInactive = color(Design.tokenTextInactive)
            palette.tokenBorder = color(Design.tokenBase.blended(
                withFraction: 0.35, of: .black) ?? Design.tokenBase)
            palette.chromeText = color(Design.baseText.withAlphaComponent(0.62))
            palette.rule = color(NSColor(srgbRed: 0.85, green: 0.85,
                                         blue: 0.87, alpha: 1))
            var fills: [String: ExportColor] = [:]
            for highlight in HighlightColor.allCases {
                fills[highlight.rawValue] = color(Design.highlightFill(highlight))
            }
            palette.highlightFills = fills
        }
        return palette
    }
}
