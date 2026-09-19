import AppKit
import NumlexCore

/// r90: THE one installed-font catalog for the whole app — notebook
/// Settings (family + face), the notebook typography resolver
/// (`NotebookPalette`) and the export dialog's explicit font menus all
/// enumerate and resolve through this single type, so the three surfaces
/// can never drift apart.
///
/// Everything here is deterministic:
/// - families are the system's installed families with empty/whitespace,
///   control-character and hidden dot-prefixed names removed, families
///   without any usable face omitted (they can never be rendered),
///   deduplicated, sorted localized-case-insensitively;
/// - faces keep the exact PostScript name (used to instantiate the font)
///   plus the user-facing label, are deduplicated by PostScript name and
///   sorted with a deterministic REGULAR preference first (a face whose
///   label reads Regular/Roman/Book/Normal), then by label;
/// - resolution accepts a family only when it is installed and a face
///   only when it belongs to that family, so a stale persisted name can
///   never leak a face from a different font.
///
/// The name/ordering rules themselves live in the dependency-free core
/// (`InstalledFontNames`) so they are unit-testable; this type adapts
/// AppKit's member rows to them and owns the AppKit font resolution.
///
/// Every failure path is safe: an unavailable family returns the
/// caller's fallback font, an unavailable face falls back to the
/// family's preferred regular face, and a family with no usable face
/// returns the fallback too. No path crashes or silently switches
/// families.
final class InstalledFontCatalog: Sendable {
    /// One installed face: the exact PostScript name used to instantiate
    /// the font, and the human-readable label shown in menus.
    struct Face: Identifiable, Equatable, Sendable {
        let name: String
        let label: String
        var id: String { name }
    }

    /// The one shared instance. Immutable after `init` (both stored
    /// properties are `let` collections of `Sendable` values), so it is
    /// safe to read from any thread.
    static let shared = InstalledFontCatalog()

    /// Every installed family, deduplicated and stably sorted.
    let families: [String]

    private let facesByFamily: [String: [Face]]

    init(families rawFamilies: [String] = NSFontManager.shared.availableFontFamilies,
         members: (String) -> [[Any]] = {
             NSFontManager.shared.availableMembers(ofFontFamily: $0) ?? []
         }) {
        // The name/ordering rules live in the dependency-free core
        // (`InstalledFontNames`) so they are unit-testable; this type only
        // adapts AppKit's `[[Any]]` member rows to `[[String]]`. A family
        // is listed only when it is a usable, non-hidden name AND has at
        // least one usable face, so `families`, `contains`, `faces` and
        // the fallback all agree that a face-less family is unavailable.
        let resolved = InstalledFontNames.families(rawFamilies) { family in
            members(family).compactMap { member in
                member.compactMap { $0 as? String }
            }
        }
        families = resolved.map(\.name)
        facesByFamily = Dictionary(uniqueKeysWithValues: resolved.map { family in
            (family.name, family.faces.map { Face(name: $0.name, label: $0.label) })
        })
    }

    /// The faces of one family in menu order (empty for nil, an unknown
    /// family or a family with no usable member).
    func faces(for family: String?) -> [Face] {
        guard let family, let faces = facesByFamily[family] else { return [] }
        return faces
    }

    /// Whether a family is installed (and usable).
    func contains(family: String?) -> Bool {
        guard let family else { return false }
        return facesByFamily[family] != nil
    }

    /// The deterministic REGULAR face of one family: the first face in
    /// menu order (regular-preferring), or nil when the family has none.
    func regularFace(for family: String?) -> Face? {
        faces(for: family).first
    }

    /// Resolves a family/face pair to a concrete font.
    ///
    /// - `family == nil`, an unavailable family, or a family without a
    ///   usable face returns `fallback` (the caller's notebook font);
    /// - a `face` is honoured only when it belongs to the installed
    ///   family — otherwise the family's preferred regular face is used,
    ///   and a family whose members cannot be instantiated at all also
    ///   returns `fallback`.
    func font(family: String?, face: String?, size: Double,
              fallback: @autoclosure () -> NSFont) -> NSFont {
        guard let family, contains(family: family) else { return fallback() }
        if let face, faces(for: family).contains(where: { $0.name == face }),
           let font = NSFont(name: face, size: size) {
            return font
        }
        if let regular = regularFace(for: family),
           let font = NSFont(name: regular.name, size: size) {
            return font
        }
        return fallback()
    }

    /// r90: the bold companion of one resolved face, for headings and
    /// total rows. The trait is derived from the SELECTED face through
    /// `NSFontManager`, which stays inside the same family whenever the
    /// family ships a bold member; when it does not, the base face is
    /// returned unchanged rather than switching families.
    static func boldVariant(of base: NSFont) -> NSFont {
        let converted = NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
        // Guard against a manager that hands back a different family: the
        // requested weight must never change the user's chosen typeface.
        if converted.familyName == base.familyName { return converted }
        return base
    }

    /// r90: the heavy companion of one resolved face (totals ask for a
    /// heavier weight than headings). The weight is requested through the
    /// font descriptor, which stays inside the SAME family when that
    /// family ships a heavier member; otherwise the bold variant and
    /// finally the base face are used — never another family.
    static func heavyVariant(of base: NSFont) -> NSFont {
        let traits: [NSFontDescriptor.TraitKey: Any] = [
            .weight: NSFont.Weight.heavy.rawValue,
        ]
        let descriptor = base.fontDescriptor.addingAttributes([.traits: traits])
        if let heavy = NSFont(descriptor: descriptor, size: base.pointSize),
           heavy.familyName == base.familyName {
            return heavy
        }
        return boldVariant(of: base)
    }

    /// The canonical regular preference (delegated to the pure core rule).
    static func regularRank(_ label: String) -> Int {
        InstalledFontNames.regularRank(label)
    }

    /// Whether a family name is hidden (delegated to the pure core rule).
    static func isHidden(_ name: String) -> Bool {
        InstalledFontNames.isHidden(name)
    }
}
