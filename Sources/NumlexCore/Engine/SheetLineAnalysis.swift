import Foundation

/// One declared tag on a sheet row: the exact source spelling, its
/// normalized lookup key and the UTF-16 spans inside the ORIGINAL line.
public struct LineTag: Equatable, Sendable {
    /// The identifier as written (without the `#`).
    public let spelling: String
    /// NFC-normalized, case-folded lookup key.
    public let key: String
    /// The full `#tag` span in the source line.
    public let span: NSRange
    /// The identifier span (without the `#`).
    public let nameSpan: NSRange

    public init(spelling: String, key: String, span: NSRange, nameSpan: NSRange) {
        self.spelling = spelling
        self.key = key
        self.span = span
        self.nameSpan = nameSpan
    }
}

/// The structural kind of one logical source line. This is the ONE
/// shared classification used by evaluation, resolution, syntax
/// classification, the UI, tokens, aggregates and export.
public enum SheetLineKind: Equatable, Sendable {
    case blank
    /// Exactly `# ` at the start of the line.
    case heading
    /// `// ` (a titled comment).
    case commentTitle
    /// `//` (a quiet comment).
    case comment
    /// A standalone exact `---` (outer spaces tolerated).
    case divider
    /// The line BODY (tags stripped) is empty but the line carried tags.
    case tagOnly
    /// A standalone legacy `total` command.
    case totalCommand
    case expression
}

/// The immutable parse of one logical line. `evaluationProjection` is
/// the source the evaluator sees (terminal tag suffix removed);
/// `body` keeps the original spelling of the evaluated part. Spans are
/// UTF-16 offsets into the ORIGINAL source line.
public struct SheetLineAnalysis: Equatable, Sendable {
    public let source: String
    public let kind: SheetLineKind
    /// Source text the evaluator consumes: the heading marker removed
    /// (heading body), or the body with the terminal tag suffix
    /// removed. Empty for blank/comments/divider.
    public let evaluationProjection: String
    /// The source WITHOUT the terminal tag suffix (original spelling),
    /// with headings/comments left intact for callers that need them.
    public let body: String
    public let tags: [LineTag]
    /// The span of the removed terminal tag suffix (from the first
    /// `#` to the end of the line), when tags were removed.
    public let tagSuffixSpan: NSRange?
    /// `# ` heading marker span (2 chars) when kind == .heading.
    public let headingMarkerSpan: NSRange?
    /// Heading body span (after `# `).
    public let headingBodySpan: NSRange?
    /// The exact `---` span (outer whitespace trimmed) for dividers.
    public let dividerSpan: NSRange?
    /// Package 7: the UTF-16 delta between a position in
    /// `evaluationProjection` and the ORIGINAL source line
    /// (`original = projectionOffset + position`). Non-zero when the
    /// projection starts after a heading marker or after leading
    /// whitespace stripped from a tagged row's prefix; the resolver
    /// adds it so marker sidecar lookups keep their document offsets.
    public let projectionOffset: Int

    public var isHeading: Bool { kind == .heading }
    public var isDivider: Bool { kind == .divider }
    public var hasTags: Bool { !tags.isEmpty }

    public static let tagMaxGraphemes = 64

    /// Parses one logical line. Pure and allocation-light; both the
    /// engine and the UI call this SAME function.
    public static func parse(_ source: String) -> SheetLineAnalysis {
        let trimmed = source.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return SheetLineAnalysis(source: source, kind: .blank,
                                     evaluationProjection: "", body: source,
                                     tags: [], tagSuffixSpan: nil,
                                     headingMarkerSpan: nil, headingBodySpan: nil,
                                     dividerSpan: nil, projectionOffset: 0)
        }
        // Exact standalone divider: outer whitespace tolerated, exactly
        // three dashes. Four or more dashes are an ordinary row.
        if trimmed == "---" {
            let ns = source as NSString
            let range = ns.range(of: "---")
            return SheetLineAnalysis(source: source, kind: .divider,
                                     evaluationProjection: "", body: source,
                                     tags: [], tagSuffixSpan: nil,
                                     headingMarkerSpan: nil, headingBodySpan: nil,
                                     dividerSpan: range, projectionOffset: 0)
        }
        if source.hasPrefix("# ") {
            let marker = NSRange(location: 0, length: 2)
            let bodyRange = NSRange(location: 2,
                                    length: (source as NSString).length - 2)
            return SheetLineAnalysis(source: source, kind: .heading,
                                     evaluationProjection: (source as NSString)
                                        .substring(with: bodyRange),
                                     body: source, tags: [], tagSuffixSpan: nil,
                                     headingMarkerSpan: marker,
                                     headingBodySpan: bodyRange, dividerSpan: nil,
                                     projectionOffset: 2)
        }
        if source.hasPrefix("//") {
            let kind: SheetLineKind = source.hasPrefix("// ") ? .commentTitle : .comment
            return SheetLineAnalysis(source: source, kind: kind,
                                     evaluationProjection: "", body: source,
                                     tags: [], tagSuffixSpan: nil,
                                     headingMarkerSpan: nil, headingBodySpan: nil,
                                     dividerSpan: nil, projectionOffset: 0)
        }
        // Terminal tag suffix: parse backwards over whitespace-separated
        // tokens; only a token that is exactly `#<valid identifier>` is
        // a tag.
        let ns = source as NSString
        var tags: [LineTag] = []
        var seen = Set<String>()
        var suffixStart: Int? = nil
        var cursor = ns.length
        while cursor > 0 {
            // Skip whitespace before the token.
            var tokenEnd = cursor
            while tokenEnd > 0,
                  isWhitespace(ns.character(at: tokenEnd - 1)) {
                tokenEnd -= 1
            }
            guard tokenEnd > 0 else { break }
            var tokenStart = tokenEnd
            while tokenStart > 0,
                  !isWhitespace(ns.character(at: tokenStart - 1)) {
                tokenStart -= 1
            }
            let tokenRange = NSRange(location: tokenStart, length: tokenEnd - tokenStart)
            let token = ns.substring(with: tokenRange)
            guard token.hasPrefix("#"),
                  let identifierSpan = validTagIdentifierSpan(token: token,
                                                              tokenRange: tokenRange) else {
                break
            }
            let name = NSString(string: token).substring(from: 1)
            let key = name.precomposedStringWithCanonicalMapping.lowercased()
            let tag = LineTag(spelling: name, key: key,
                              span: tokenRange, nameSpan: identifierSpan)
            if let existing = tags.firstIndex(where: { $0.key == key }) {
                // Duplicate on one row: the EARLIER source occurrence
                // wins (the right-to-left scan sees later ones first).
                tags[existing] = tag
            } else {
                seen.insert(key)
                tags.insert(tag, at: 0)
            }
            suffixStart = tokenStart
            cursor = tokenStart
        }
        guard let start = suffixStart, !tags.isEmpty else {
            return SheetLineAnalysis(source: source, kind: .expression,
                                     evaluationProjection: source, body: source,
                                     tags: [], tagSuffixSpan: nil,
                                     headingMarkerSpan: nil, headingBodySpan: nil,
                                     dividerSpan: nil, projectionOffset: 0)
        }
        let suffix = NSRange(location: start,
                             length: (source as NSString).length - start)
        let prefix = (source as NSString).substring(to: start)
        let body = prefix.trimmingCharacters(in: .whitespaces)
        // Package 7: the projection keeps the ORIGINAL prefix
        // coordinates — leading whitespace must not shift marker
        // sidecar lookups (`  U+FFFC + 1 #tag`). Only the terminal
        // separator/tag suffix is removed; the offset records the
        // stripped prefix so `projectionOffset + pos` is the original
        // UTF-16 position.
        var leadingUTF16 = 0
        for ch in prefix {
            let isSpace = ch == " " || ch == "\t"
            guard isSpace else { break }
            leadingUTF16 += ch.utf16.count
        }
        let kind: SheetLineKind = body.isEmpty ? .tagOnly : .expression
        return SheetLineAnalysis(source: source, kind: kind,
                                 evaluationProjection: body, body: body,
                                 tags: tags, tagSuffixSpan: suffix,
                                 headingMarkerSpan: nil, headingBodySpan: nil,
                                 dividerSpan: nil,
                                 projectionOffset: body.isEmpty ? 0 : leadingUTF16)
    }

    /// A token is a tag only when it is `#` + a valid identifier. The
    /// identifier is validated in its CANONICAL NFC form (a decomposed
    /// `#cafe\u0301` is a valid tag) while the original spelling and
    /// source spans are preserved for display and highlighting.
    private static func validTagIdentifierSpan(token: String,
                                               tokenRange: NSRange) -> NSRange? {
        let rawName = String(token.dropFirst())
        guard !rawName.isEmpty else { return nil }
        let name = rawName.precomposedStringWithCanonicalMapping
        let graphemes = Array(name)
        guard graphemes.count <= SheetLineAnalysis.tagMaxGraphemes else { return nil }
        guard let first = graphemes.first,
              first.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) })
        else { return nil }
        let allowed = CharacterSet.letters
            .union(.decimalDigits)
            .union(CharacterSet(charactersIn: "_-"))
        for ch in graphemes.dropFirst() {
            guard ch.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        }
        return NSRange(location: tokenRange.location + 1,
                       length: tokenRange.length - 1)
    }

    private static func isWhitespace(_ unit: unichar) -> Bool {
        guard let scalar = UnicodeScalar(unit) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }
}
