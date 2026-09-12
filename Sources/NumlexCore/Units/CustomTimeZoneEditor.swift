import Foundation

// MARK: - Custom timezone editor (temporal Task 1)
//
// The pure validation/editing model behind the Dates & Times Settings
// destination. The UI, the AppModel mutation API and the tests all share
// this ONE source of truth for what a custom timezone row means, so the
// editor can never declare a row usable that the TimezoneLane would
// reject (or vice versa).

/// The validation state of one custom-timezone row. Rendered as a status
/// label; `active` is the only state that participates in evaluation.
public enum CustomTimeZoneState: Equatable, Sendable {
    /// Both fields are empty: a fresh row the user has not started.
    case empty
    /// Exactly one of the two fields is filled.
    case incomplete
    /// The name cannot be an alias (bad characters, too long, no letter).
    case invalidName
    /// Another row already uses this name (case/whitespace-insensitive).
    case duplicate
    /// The name would steal a bundled city/country/airport/IANA/fixed
    /// abbreviation or a GMT/UTC offset syntax.
    case builtInCollision
    /// The identifier is not a timezone Foundation knows.
    case unknownZone
    /// Valid: name + known IANA identifier, no conflicts.
    case active

    /// Whether the row contributes an alias to the lane.
    public var isActive: Bool { self == .active }
}

/// The shared custom-timezone editing rules.
public enum CustomTimeZoneEditor {
    /// The maximum alias length (matches the lane's bounded input).
    public static let maxNameLength = 60
    /// The maximum identifier length (the longest real IANA id is 32).
    public static let maxIdentifierLength = 64

    /// The canonical comparison key: trimmed, lowercased, whitespace runs
    /// collapsed to one space. Two names with the same key are the SAME
    /// alias regardless of case or spacing.
    public static func canonicalName(_ raw: String) -> String {
        raw.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// Whether a name could ever be an alias: 1...60 characters starting
    /// with a letter and containing only letters, digits, spaces, `-`,
    /// `'`, `.`, `_`, `+`. Empty is `invalidName` here; the caller maps
    /// the both-empty case to `.empty` first.
    public static func isValidNameShape(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= maxNameLength else { return false }
        guard let first = trimmed.unicodeScalars.first,
              CharacterSet.letters.contains(first) else { return false }
        let allowed = CharacterSet.letters
            .union(.decimalDigits)
            .union(CharacterSet(charactersIn: " -'._+"))
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// A name that resolves through the built-in sources: IANA id/alias,
    /// city, country name/code, IATA/ICAO, fixed abbreviation or GMT/UTC
    /// offset syntax. Such a name would shadow bundled data, so it is
    /// never accepted as a custom alias.
    public static func isBuiltInName(_ raw: String,
                                     catalog: TimezoneCatalog? = TimezoneCatalog.shared) -> Bool {
        guard let catalog else { return false }
        // Reuse the lane's own resolver with an EMPTY custom list: exactly
        // the sources a user alias must not steal.
        return TimezoneLane.resolveZone(raw, catalog: catalog,
                                        preferences: .defaults) != nil
    }

    /// The state of ONE row. `excluding` skips the row's own ID for the
    /// duplicate check.
    public static func state(name: String, identifier: String,
                             zones: [CustomTimeZone] = [],
                             excluding id: UUID? = nil,
                             catalog: TimezoneCatalog? = TimezoneCatalog.shared)
        -> CustomTimeZoneState {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedID = identifier.trimmingCharacters(in: .whitespaces)
        if trimmedName.isEmpty && trimmedID.isEmpty { return .empty }
        if trimmedName.isEmpty || trimmedID.isEmpty { return .incomplete }
        guard isValidNameShape(trimmedName) else { return .invalidName }
        let key = canonicalName(trimmedName)
        for zone in zones where zone.id != id {
            if canonicalName(zone.name) == key { return .duplicate }
        }
        if isBuiltInName(trimmedName, catalog: catalog) { return .builtInCollision }
        guard TimeZone(identifier: trimmedID) != nil else { return .unknownZone }
        return .active
    }

    /// Every row's state in one pass (row order preserved).
    public static func states(_ zones: [CustomTimeZone],
                              catalog: TimezoneCatalog? = TimezoneCatalog.shared)
        -> [CustomTimeZoneState] {
        zones.map { state(name: $0.name, identifier: $0.identifier,
                          zones: zones, excluding: $0.id, catalog: catalog) }
    }

    /// The alias a fresh row gets: `Alias`, `Alias 2`, ... — collision-free
    /// against the current custom names AND the built-in sources, so the
    /// generated row never opens on a validation error.
    public static func generatedName(taken: Set<String>,
                                     catalog: TimezoneCatalog? = TimezoneCatalog.shared) -> String {
        let base = "Alias"
        if !taken.contains(canonicalName(base)),
           !isBuiltInName(base, catalog: catalog) {
            return base
        }
        var n = 2
        while n < 10_000 {
            let candidate = "\(base) \(n)"
            if !taken.contains(canonicalName(candidate)),
               !isBuiltInName(candidate, catalog: catalog) {
                return candidate
            }
            n += 1
        }
        return "\(base) \(n)"
    }

    /// The active aliases only, in row order: what the lane consumes.
    public static func activeZones(_ zones: [CustomTimeZone],
                                   catalog: TimezoneCatalog? = TimezoneCatalog.shared)
        -> [CustomTimeZone] {
        let all = states(zones, catalog: catalog)
        return zip(zones, all).compactMap { state in
            state.1.isActive ? state.0 : nil
        }
    }
}
