import Foundation

/// r73: safe, idempotent foreign-number conversion for EXTERNAL plain
/// text pasted into the notebook (only when the user's
/// `convertForeignOnPaste` toggle is ON and the active context is
/// non-legacy). The app layer routes internal (Numlex token) pastes
/// around this pass entirely.
///
/// Reading a candidate span (digit runs interleaved with `,`, `.` and
/// space/NBSP separators — the strict grammar below, so prose,
/// identifiers, URLs and `sum(1, 2)` argument lists never match):
/// - the RIGHTMOST separator is the decimal point when it is a `,` or
///   a `.` (a three-digit tail after a dot still counts as fraction,
///   `1,234.567` → 1234.567); a rightmost space group defers to the
///   rightmost `,` / `.` in the span;
/// - a span whose ONLY separator kind is comma groups (`1,234`,
///   `1,234,567`) carries no decimal at all — those commas are
///   grouping, exactly like in the source locale;
/// - the remaining separators are the GROUPING kind: one kind per
///   span, and dot groups must run exactly three digits (`1.23,56`
///   is inconsistent and stays untouched);
/// - a rightmost dot with a non-three-digit tail in an otherwise
///   dot-only span is the decimal point (`1.23` stays `1.23` under a
///   dot target — untouched; a comma target re-renders it `1,23`).
///
/// The span is re-rendered in the TARGET conventions (decimal
/// separator, grouping separator per the display toggle); a span that
/// already renders identically comes back byte-identical — the pass
/// is idempotent.
public enum PasteConversion {

    public static func convert(_ text: String,
                               context: NumberFormatContext) -> String {
        guard !context.legacy, context.convertForeignOnPaste else { return text }
        return text.components(separatedBy: "\n")
            .map { convertLine($0, context: context) }
            .joined(separator: "\n")
    }

    // MARK: - Line pass

    private static func convertLine(_ line: String,
                                    context: NumberFormatContext) -> String {
        guard let regex = try? NSRegularExpression(pattern: spanPattern,
                                                   options: []) else {
            return line
        }
        let ns = line as NSString
        var result = line
        let full = NSRange(location: 0, length: ns.length)
        for m in regex.matches(in: line, range: full).reversed() {
            let span = ns.substring(with: m.range)
            let rendered = render(span, context: context) ?? span
            guard rendered != span,
                  let r = Range(m.range, in: result) else { continue }
            result.replaceSubrange(r, with: rendered)
        }
        return result
    }

    /// The strict candidate grammar: a 1-3 digit lead, then separator
    /// runs — comma groups (`,` + 3 digits), dot runs (`.` + digits) or
    /// space/NBSP groups — with an optional second separator tail
    /// (the dual-separator decimal). Edges never touch letters,
    /// digits, separators or spaces, so `1,234.56km` converts and
    /// `sum(1, 2)` or `x1,234` do not.
    /// The pattern embeds the NBSP and space characters directly (the
    /// ICU engine behind NSRegularExpression rejects `\u{XXXX}`
    /// escapes). Edges never touch letters, digits or the separator
    /// characters: `1,234.56km` converts, `x1,234` and `sum(1,234)`
    /// do not. Space itself IS the Eastern-Europe group separator, so
    /// a space may legally bound a span.
    private static let spanPattern =
        "(?<![A-Za-z0-9_.\u{00A0},])"
        + "(?:\\d{1,3}(?:,\\d{3})+"
        + "|\\d{1,3}(?:\\.\\d+)+"
        + "|\\d{1,3}(?:[\u{00A0} ]\\d{3})+)"
        + "(?:[,.]\\d+)?"
        + "(?![A-Za-z0-9_.\u{00A0},])"

    // MARK: - Span reading

    private enum GroupKind: Character { case comma = ",", dot = "." }

    private struct Reading {
        let intDigits: String
        let fracDigits: String?
        let hasGrouping: Bool
    }

    /// Splits the span into digit runs and separators; nil when the
    /// shape is not a consistent number (mixed group kinds, an
    /// inconsistent dot group, a separator with no digits after it).
    private static func read(_ span: String) -> Reading? {
        var runs: [String] = []
        var seps: [Character] = []
        var i = span.startIndex
        guard i < span.endIndex, span[i].isNumber else { return nil }
        while true {
            let s = i
            while i < span.endIndex, span[i].isNumber { i = span.index(after: i) }
            runs.append(String(span[s..<i]))
            if i >= span.endIndex { break }
            let sep = span[i]
            guard sep == "," || sep == "." || sep == " " || sep == "\u{00A0}"
            else { return nil }
            seps.append(sep)
            i = span.index(after: i)
            guard i < span.endIndex, span[i].isNumber else { return nil }
        }
        guard !seps.isEmpty else { return nil } // the pattern requires one
        // The decimal separator: the rightmost , or . (a rightmost
        // space group defers to the rightmost , / . in the span).
        var decimalK: Int?
        let last = seps[seps.count - 1]
        if last == "," || last == "." {
            decimalK = seps.count - 1
        } else if let k = seps.lastIndex(of: ",") {
            decimalK = k
        } else if let k = seps.lastIndex(of: ".") {
            decimalK = k
        }
        // A pure comma-group span (1,234 / 1,234,567) has NO decimal:
        // every separator is a comma AND the rightmost comma's tail is
        // an exact 3-digit group. A comma decimal (1,234,56 -> the
        // final two-digit tail) is NOT a group: it keeps its decimal.
        if let k = decimalK,
           seps[k] == ",", k == seps.count - 1,
           runs[k + 1].count == 3,
           !seps.prefix(k).contains(where: { $0 != "," }) {
            decimalK = nil
        }
        // Grouping consistency: everything except the decimal
        // separator — one non-space kind per span, dot groups must
        // run exactly three digits (`1.23,56` is inconsistent).
        let groupSeps = seps.enumerated().filter { (k, _) in k != decimalK }
        var groupKind: Character?
        for (k, sep) in groupSeps {
            if sep == " " || sep == "\u{00A0}" { continue } // space groups
            if let gk = groupKind, gk != sep { return nil } // mixed
            if sep == "." {
                guard runs[k + 1].count == 3 else { return nil }
            }
            groupKind = sep
        }
        _ = groupKind
        let hasGrouping = groupSeps.count > 0
        // Assemble.
        if let dec = decimalK {
            let intDigits = runs[0...dec].joined() // digits before the decimal
            let frac = runs[(dec + 1)...].joined()
            guard !intDigits.isEmpty else { return nil }
            return Reading(intDigits: intDigits,
                           fracDigits: frac.isEmpty ? nil : frac,
                           hasGrouping: hasGrouping)
        }
        let all = runs.joined()
        return Reading(intDigits: all, fracDigits: nil,
                       hasGrouping: hasGrouping)
    }

    // MARK: - Target rendering

    /// Renders the span in the target conventions; nil when the span
    /// is not a consistent number shape (it stays untouched).
    private static func render(_ span: String,
                               context: NumberFormatContext) -> String? {
        guard let r = read(span) else { return nil }
        var out = group(r.intDigits, context: context)
        if let frac = r.fracDigits {
            out += context.decimalSeparator + frac
        }
        return out
    }

    /// Groups `digits` with the target's separator when the display
    /// toggle is on and the target has one; verbatim otherwise.
    private static func group(_ digits: String,
                              context: NumberFormatContext) -> String {
        guard context.displayGrouping,
              !context.groupingSeparator.isEmpty,
              digits.count > 3 else {
            return digits
        }
        let chars = Array(digits)
        var out = ""
        out.reserveCapacity(chars.count + chars.count / 3)
        for (idx, ch) in chars.enumerated() {
            if idx > 0, (chars.count - idx) % 3 == 0 {
                out += context.groupingSeparator
            }
            out.append(ch)
        }
        return out
    }
}
