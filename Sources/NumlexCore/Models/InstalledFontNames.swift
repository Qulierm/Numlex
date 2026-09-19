import Foundation

/// r90/r91: the PURE name/ordering rules behind the app's installed-font
/// catalog. Installed font names come from macOS and are untrusted input;
/// these rules decide which families and faces are user-selectable and in
/// what order. They live in the dependency-free core (no AppKit) so the
/// exact behavior is unit-testable, and the app's `InstalledFontCatalog`
/// delegates to them instead of duplicating the logic.
public enum InstalledFontNames {
    /// One installed face: the exact PostScript name used to instantiate
    /// the font, and the user-facing label shown in menus.
    public struct Face: Equatable, Sendable {
        public let name: String
        public let label: String
        public init(name: String, label: String) {
            self.name = name
            self.label = label
        }
    }

    /// One installed family with its deterministic face list.
    public struct Family: Equatable, Sendable {
        public let name: String
        public let faces: [Face]
        public init(name: String, faces: [Face]) {
            self.name = name
            self.faces = faces
        }
    }

    /// A usable font name: non-empty after trimming surrounding
    /// whitespace/newlines, with no control characters (macOS
    /// occasionally reports placeholder family names).
    public static func usableName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !trimmed.unicodeScalars.contains(where: {
            CharacterSet.controlCharacters.contains($0)
        }) else {
            return nil
        }
        return trimmed
    }

    /// A HIDDEN family: macOS reports private/system families with a
    /// leading dot (`.AppleSystemUIFont`, `.SF NS`, …). They are not
    /// user-selectable typefaces, so they are never listed and never
    /// treated as available. The dot is checked after trimming, exactly
    /// like every other name rule.
    public static func isHidden(_ name: String) -> Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(".")
    }

    /// Lower is "more regular": 0 for the canonical regular spellings,
    /// 1 for everything else.
    public static func regularRank(_ label: String) -> Int {
        let lower = label.lowercased()
        for token in ["regular", "roman", "book", "normal"] where lower.contains(token) {
            return 0
        }
        return 1
    }

    /// The usable, deduplicated, regular-preferring face list of ONE
    /// family. Members arrive as the `[PostScript name, label, …]` rows
    /// `NSFontManager` reports; malformed rows are skipped.
    public static func faces(fromMembers members: [[String]]) -> [Face] {
        var seen = Set<String>()
        var out: [Face] = []
        for member in members {
            guard member.count >= 2,
                  let postScriptName = usableName(member[0]) else { continue }
            guard seen.insert(postScriptName).inserted else { continue }
            let faceLabel = usableName(member[1]) ?? postScriptName
            out.append(Face(name: postScriptName, label: faceLabel))
        }
        // Regular/Roman/Book/Normal first (a deterministic base face),
        // then the remaining faces by label — so the menu, the "Regular"
        // choice and the persisted nil-face default all agree.
        return out.enumerated().sorted { lhs, rhs in
            let l = regularRank(lhs.element.label), r = regularRank(rhs.element.label)
            if l != r { return l < r }
            let byLabel = lhs.element.label.localizedCaseInsensitiveCompare(rhs.element.label)
            if byLabel != .orderedSame { return byLabel == .orderedAscending }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// The user-selectable families: empty/control names and hidden
    /// dot-prefixed names are dropped, families with NO usable face are
    /// dropped (a face-less family can never be rendered, so `families`,
    /// membership, `faces` and the fallback must all agree that it is
    /// unavailable), duplicates collapse on the case-folded name while
    /// keeping the FIRST spelling, and the result is sorted
    /// localized-case-insensitively with an exact-name tiebreaker so the
    /// order is fully deterministic.
    public static func families(_ rawFamilies: [String],
                                members: (String) -> [[String]]) -> [Family] {
        var seen = Set<String>()
        var resolved: [Family] = []
        for raw in rawFamilies {
            guard let name = usableName(raw), !isHidden(name) else { continue }
            guard seen.insert(name.lowercased()).inserted else { continue }
            let faces = faces(fromMembers: members(name))
            guard !faces.isEmpty else { continue }
            resolved.append(Family(name: name, faces: faces))
        }
        return resolved.sorted {
            let byName = $0.name.localizedCaseInsensitiveCompare($1.name)
            if byName != .orderedSame { return byName == .orderedAscending }
            return $0.name < $1.name
        }
    }
}
