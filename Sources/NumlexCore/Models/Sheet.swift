import Foundation

public struct Sheet: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var content: String
    public var createdAt: Date
    public var modifiedAt: Date
    /// True once the user explicitly renames the sheet; the title then stops
    /// following the first calculation.
    public var isTitleCustom: Bool
    /// Generic name assigned at creation — used as the fallback for
    /// automatic titles once the first calculation disappears again.
    public var titleSeed: String
    /// One stable UUID per LOGICAL line (the same split the evaluator
    /// uses, including blanks and the trailing line after a final
    /// newline). Answer tokens reference lines by this ID, never by
    /// index, so edits above must not redirect them.
    public var lineIDs: [UUID]
    /// Live answer reference tokens (U+FFFC markers + sidecar metadata),
    /// sorted by marker location.
    public var references: [AnswerReference]
    /// r39: the folder this sheet is filed in (nil = the built-in
    /// localized General group). App-local only: never part of `.nlx`
    /// exports (SheetExport deliberately has no folder key).
    public var folderID: UUID?
    /// r51: per-answer display preferences (rounding overrides), keyed
    /// by stable line UUID. Presentation-only document metadata like
    /// lineIDs/references — preserved by `.nlx` export, never global
    /// settings, never engine semantics.
    public var answerDisplay: [AnswerDisplayPreference]

    public init(id: UUID = UUID(),
                title: String,
                content: String,
                createdAt: Date = Date(),
                modifiedAt: Date = Date(),
                isTitleCustom: Bool = false,
                titleSeed: String? = nil,
                lineIDs: [UUID] = [],
                references: [AnswerReference] = [],
                folderID: UUID? = nil,
                answerDisplay: [AnswerDisplayPreference] = []) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.isTitleCustom = isTitleCustom
        self.titleSeed = titleSeed ?? title
        // Normalize: one ID per logical line, only references whose
        // marker really points at a U+FFFC in the content.
        self.lineIDs = (lineIDs.count == content.components(separatedBy: "\n").count)
            ? lineIDs
            : content.components(separatedBy: "\n").map { _ in UUID() }
        self.references = Sheet.sanitizeReferences(references, in: content)
        self.folderID = folderID
        // r51: additive — overrides survive only for lines that exist.
        self.answerDisplay = AnswerDisplay.sanitize(answerDisplay, lineIDs: self.lineIDs)
    }

    /// Drops rounding overrides whose line no longer exists (call after
    /// any content/lineID mutation: edits, deletions, imports, loads).
    public mutating func dropStaleAnswerDisplay() {
        answerDisplay = AnswerDisplay.sanitize(answerDisplay, lineIDs: lineIDs)
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, content, createdAt, modifiedAt
        case isTitleCustom, titleSeed, lineIDs, references
        case folderID
        case answerDisplay
    }

    /// Backward-compatible decoding: stores saved before the naming feature
    /// have no `isTitleCustom`/`titleSeed` keys. A meaningful saved title
    /// (anything that is not a generic "Sheet"/"Sheet N" in any supported
    /// language) migrates as custom; generic names stay automatic.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        content = try c.decode(String.self, forKey: .content)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
        if let custom = try c.decodeIfPresent(Bool.self, forKey: .isTitleCustom) {
            isTitleCustom = custom
        } else {
            isTitleCustom = !Sheet.isGenericTitle(title)
        }
        titleSeed = try c.decodeIfPresent(String.self, forKey: .titleSeed) ?? title
        // Backward-compatible: stores saved before the reference-token
        // feature carry neither key. Line IDs regenerate per logical
        // line; references are sanitized against the actual content so a
        // corrupted payload can never carry dead markers.
        let storedLineIDs = try c.decodeIfPresent([UUID].self, forKey: .lineIDs) ?? []
        let lineCount = content.components(separatedBy: "\n").count
        lineIDs = (storedLineIDs.count == lineCount)
            ? storedLineIDs
            : content.components(separatedBy: "\n").map { _ in UUID() }
        let storedRefs = try c.decodeIfPresent([AnswerReference].self, forKey: .references) ?? []
        references = Sheet.sanitizeReferences(storedRefs, in: content)
        // r39: additive and failure-proof — pre-r39 stores carry no
        // `folderID` key (decode nil = General), and a wrong-typed value
        // must fall back to General instead of failing the sheet.
        folderID = (try? c.decodeIfPresent(UUID.self, forKey: .folderID)) ?? nil
        // r51: additive and failure-proof — pre-r51 stores carry no
        // `answerDisplay` key (decode []), a wrong-typed value falls
        // back to [] instead of failing the sheet, and stale/clamped
        // entries are sanitized against the final line table.
        let storedDisplay: [AnswerDisplayPreference] = (try? c.decodeIfPresent([AnswerDisplayPreference].self, forKey: .answerDisplay)) ?? []
        answerDisplay = AnswerDisplay.sanitize(storedDisplay, lineIDs: lineIDs)
    }

    /// One entry per logical line (the evaluator's split), including the
    /// single blank line of an empty document.
    public var logicalLineCount: Int {
        content.components(separatedBy: "\n").count
    }

    /// Keeps only references whose `location` really points at a U+FFFC
    /// marker in `content`, sorted by location.
    public static func sanitizeReferences(_ refs: [AnswerReference], in content: String) -> [AnswerReference] {
        let ns = content as NSString
        let kept = refs.filter { r in
            r.location >= 0 && r.location < ns.length
                && ns.character(at: r.location) == answerTokenMarkerUTF16
        }
        return kept.sorted { $0.location < $1.location }
    }

    // MARK: Automatic titles

    /// Generic title bases in every supported language.
    private static let genericBases = ["Sheet", "Лист", "Blatt", "Feuille", "Foglio", "工作表"]

    /// True for "Sheet", "Sheet 2", "Лист 3", … — titles the app itself
    /// could have generated, as opposed to user-meaningful names.
    public static func isGenericTitle(_ title: String) -> Bool {
        var base = title.trimmingCharacters(in: .whitespaces)
        if let spaceIdx = base.lastIndex(of: " "), spaceIdx > base.startIndex {
            let tail = base[base.index(after: spaceIdx)...]
            if !tail.isEmpty, tail.allSatisfy({ $0.isNumber }) {
                base = String(base[..<spaceIdx])
            }
        }
        return genericBases.contains(base)
    }

    /// Derives a sheet title from the FIRST calculable nonblank logical line
    /// (expression, assignment, conversion or valid weather query).
    /// Skips blanks, `#` comments, `//` headings, plain notes and error
    /// lines. The line is trimmed, whitespace-collapsed and safely
    /// truncated. r33: with `constants` a first calculation USING a
    /// global constant is recognized. r55: a valid `weather in <place>`
    /// query titles the sheet even before any network completes (pure
    /// parse, never a fetch).
    public static func autoTitle(from content: String, fallback: String,
                                 constants: [UserConstant] = []) -> String {
        // ONE shared typed environment (named unitless values AND money)
        // so natural lines evaluate the same way as in the sheet.
        var env = TypedEnv()
        env.seedConstants(constants)
        for rawLine in content.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("#") || line.hasPrefix("//") { continue }
            if WeatherQuery.parse(line) != nil {
                let collapsed = line
                    .split(whereSeparator: { $0.isWhitespace })
                    .joined(separator: " ")
                if collapsed.count <= 28 { return collapsed }
                return String(collapsed.prefix(27)) + "…"
            }
            guard let result = evalLineTyped(line, env: &env, rates: Rates(),
                                             decimalPlaces: 7, now: Date(),
                                             calendar: Calendar.current) else { continue }
            switch result {
            case .number, .variable, .money, .date:
                let collapsed = line
                    .split(whereSeparator: { $0.isWhitespace })
                    .joined(separator: " ")
                if collapsed.count <= 28 { return collapsed }
                return String(collapsed.prefix(27)) + "…"
            default:
                continue
            }
        }
        return fallback
    }

    /// Applies the automatic-title rule to a sheet whose content changed:
    /// re-derives the title unless the user renamed it explicitly.
    public static func retitled(_ sheet: Sheet, content: String,
                                constants: [UserConstant] = []) -> Sheet {
        var s = sheet
        guard !s.isTitleCustom else { return s }
        let derived = autoTitle(from: content, fallback: s.titleSeed,
                                constants: constants)
        if derived != s.title { s.title = derived }
        return s
    }

    /// Migrates a legacy sheet into the canonical notebook form:
    /// mathematical lines are canonicalized (visible `*` becomes `×`,
    /// operators get spaced) and the automatic title is re-derived from
    /// the canonical text. Prose, comments and conversions are untouched.
    /// Returns the migrated sheet and whether anything changed.
    public static func canonicalized(_ sheet: Sheet) -> (sheet: Sheet, changed: Bool) {
        let content = NotebookFormatting.canonicalDocument(sheet.content)
        guard content != sheet.content else { return (sheet, false) }
        var migrated = sheet
        migrated.content = content
        return (retitled(migrated, content: content), true)
    }

    /// Title shown in the sidebar. Automatic sheets without any content
    /// display the localized "Empty" name (covers new sheets, the reset of
    /// the last remaining sheet, cleared content and migrated legacy
    /// generic titles); explicit custom titles are always shown as-is, even
    /// for empty content.
    public func displayTitle(language: AppLanguage) -> String {
        if isTitleCustom { return title }
        return lineCount == 0 ? L10n.t("empty", language: language) : title
    }

    public var lineCount: Int {
        if content.isEmpty { return 0 }
        let parts = content.components(separatedBy: "\n")
        if parts.count == 1 && parts[0].isEmpty { return 0 }
        return parts.count
    }

    public var createdLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        if Calendar.current.isDateInToday(createdAt) {
            f.dateFormat = "HH:mm"
        } else {
            f.dateFormat = "MMM d 'at' HH:mm"
        }
        return f.string(from: createdAt)
    }
}

public struct SheetExport: Codable, Sendable {
    public var title: String
    public var content: String
    /// Optional so files exported before the naming feature still decode.
    public var isTitleCustom: Bool?
    /// Line identity + live reference tokens: optional so files exported
    /// before the reference-token feature still decode.
    public var lineIDs: [UUID]?
    public var references: [AnswerReference]?
    /// r51: per-answer display preferences (optional so older files
    /// decode with nil = no overrides). Folder metadata stays excluded.
    public var answerDisplay: [AnswerDisplayPreference]?

    public init(title: String,
                content: String,
                isTitleCustom: Bool? = nil,
                lineIDs: [UUID]? = nil,
                references: [AnswerReference]? = nil,
                answerDisplay: [AnswerDisplayPreference]? = nil) {
        self.title = title
        self.content = content
        self.isTitleCustom = isTitleCustom
        self.lineIDs = lineIDs
        self.references = references
        self.answerDisplay = answerDisplay
    }
}
