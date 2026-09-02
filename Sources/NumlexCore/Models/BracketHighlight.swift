import Foundation

/// Pure, AppKit-free matching-bracket model for the notebook editor
/// (r48). Everything the editor draws from — the pair resolution and
/// the pulse time curve — lives here so it is testable standalone.
///
/// The input contract is a document `String` plus a bounds-validated
/// `NSRange`. Only exactly one COLLAPSED selection (length 0) can ever
/// match; a nonempty/multiple selection, an out-of-range caret, or a
/// caret that splits a surrogate pair always yields `nil`. Only the
/// ASCII bracket pairs `()`, `[]`, `{}` participate, and a match never
/// crosses a line break — notebook lines are independent calculations.
/// U+FFFC answer tokens and any Unicode/emoji content are neutral
/// UTF-16 content: they occupy units, never match, and never interfere
/// with the walk.
public struct BracketPair: Equatable, Hashable, Sendable {
    /// Which bracket the caret touched: the OPENING mate is the
    /// slightly emphasized one (the closing/anchor reads clearly too).
    public enum Role: Equatable, Hashable, Sendable {
        case opening
        case closing
    }

    /// UTF-16 offset of the opening bracket in the document.
    public let opening: Int
    /// UTF-16 offset of the closing bracket in the document.
    public let closing: Int
    /// The bracket the caret is adjacent to (the interacted one).
    public let role: Role

    public init(opening: Int, closing: Int, role: Role) {
        self.opening = opening
        self.closing = closing
        self.role = role
    }
}

public enum BracketHighlight {
    // MARK: - Bracket characters (ASCII only)

    public static let openingUnits: Set<UInt16> = [0x28, 0x5B, 0x7B]   // ( [ {
    public static let closingUnits: Set<UInt16> = [0x29, 0x5D, 0x7D]   // ) ] }

    /// The opening unit a closing unit matches (and vice versa).
    static func mate(of unit: UInt16) -> UInt16? {
        switch unit {
        case 0x28: return 0x29
        case 0x29: return 0x28
        case 0x5B: return 0x5D
        case 0x5D: return 0x5B
        case 0x7B: return 0x7D
        case 0x7D: return 0x7B
        default: return nil
        }
    }

    static func isLineBreak(_ unit: UInt16) -> Bool {
        unit == 0x0A || unit == 0x0D   // \n, \r (CRLF counts at both units)
    }

    /// Resolves the matching pair for the caret at `selection` in
    /// `document`, or `nil` when no pair is active (invalid selection,
    /// no adjacent bracket, unmatched/mismatched/crossed brackets, or
    /// the mate is on another logical line).
    ///
    /// Caret-adjacency priority (real click placement): the closing
    /// bracket immediately BEFORE the caret (normal typing / right-half
    /// click on a closing glyph) wins, then the closing bracket AT the
    /// caret (left-half click), then the opening bracket AT the caret,
    /// then the opening bracket immediately BEFORE the caret. Clicking
    /// either half of a closing glyph therefore always identifies its
    /// opening mate. The walk is O(current line) — one bounded scan per
    /// actual selection change, never per frame.
    public static func pair(document: String, selection: NSRange) -> BracketPair? {
        let u16 = Array(document.utf16)
        let len = u16.count
        guard selection.length == 0,
              selection.location >= 0,
              selection.location <= len else { return nil }
        let p = selection.location
        // A caret that splits a surrogate pair is invalid/stale: the
        // high unit at p-1 belongs to the same scalar as the low unit at
        // p, so the caret cannot legally sit between them.
        if p > 0, p < len,
           (0xD800...0xDBFF).contains(u16[p - 1]),
           (0xDC00...0xDFFF).contains(u16[p]) {
            return nil
        }

        // Logical-line bounds: the walk may never cross a line break
        // (CR, LF or CRLF). O(line length).
        var lineStart = p
        while lineStart > 0, !isLineBreak(u16[lineStart - 1]) { lineStart -= 1 }
        var lineEnd = p
        while lineEnd < len, !isLineBreak(u16[lineEnd]) { lineEnd += 1 }

        // Adjacency priority (see above).
        if p > 0, closingUnits.contains(u16[p - 1]) {
            return matchClosing(at: p - 1, in: u16, lineStart: lineStart, lineEnd: lineEnd)
        }
        if p < len, closingUnits.contains(u16[p]) {
            return matchClosing(at: p, in: u16, lineStart: lineStart, lineEnd: lineEnd)
        }
        if p < len, openingUnits.contains(u16[p]) {
            return matchOpening(at: p, in: u16, lineStart: lineStart, lineEnd: lineEnd)
        }
        if p > 0, openingUnits.contains(u16[p - 1]) {
            return matchOpening(at: p - 1, in: u16, lineStart: lineStart, lineEnd: lineEnd)
        }
        return nil
    }

    /// Finds the opening mate of the CLOSING bracket at `c` by a single
    /// left-to-right stack walk from the line start to `c`. A mismatched
    /// closing (top of the stack does not match) fails the whole match —
    /// a crossed or malformed region can never yield a false pair. A
    /// stray closing with an empty stack is skipped: it cannot consume
    /// an opening, so it can never create a false pairing.
    static func matchClosing(at c: Int, in u16: [UInt16],
                             lineStart: Int, lineEnd: Int) -> BracketPair? {
        var stack: [(unit: UInt16, pos: Int)] = []
        var i = lineStart
        while i < c {
            let ch = u16[i]
            if openingUnits.contains(ch) {
                stack.append((ch, i))
            } else if closingUnits.contains(ch) {
                if let top = stack.last {
                    if mate(of: top.unit) == ch {
                        stack.removeLast()
                    } else {
                        return nil   // mismatch: no false pair
                    }
                }
                // else stray closing: skip (nothing to consume)
            }
            i += 1
        }
        guard let top = stack.last, mate(of: top.unit) == u16[c] else { return nil }
        return BracketPair(opening: top.pos, closing: c, role: .closing)
    }

    /// Finds the closing mate of the OPENING bracket at `o` by a single
    /// forward stack walk to the line end. The anchor itself is pushed
    /// first, so the stack is never empty here: any mismatched closing
    /// fails the match (a crossed region can never yield a false pair),
    /// and the first closing that pops the anchor is the pair.
    static func matchOpening(at o: Int, in u16: [UInt16],
                             lineStart: Int, lineEnd: Int) -> BracketPair? {
        var stack: [(unit: UInt16, pos: Int)] = [(u16[o], o)]
        var i = o + 1
        while i < lineEnd {
            let ch = u16[i]
            if openingUnits.contains(ch) {
                stack.append((ch, i))
            } else if closingUnits.contains(ch) {
                if let top = stack.last {
                    if mate(of: top.unit) == ch {
                        if top.pos == o {
                            return BracketPair(opening: o, closing: i, role: .opening)
                        }
                        stack.removeLast()
                    } else {
                        return nil   // mismatch: no false pair
                    }
                }
            }
            i += 1
        }
        return nil   // anchor never closed within the logical line
    }

    // MARK: - Pulse curve (deterministic, finite, clamped)

    /// The one bounded pulse per pair change: ~0.33 s (within the
    /// requested 0.30–0.36 s window). Subtle scale from 0.86 through a
    /// small overshoot to 1; the fill opacity settles to the static
    /// highlight.
    public static let pulseDuration: TimeInterval = 0.33
    /// Scale at pulse start (the final scale is 1).
    public static let pulseStartScale: Double = 0.86
    /// Mid-pulse scale overshoot above the eased base (peak ≈ +0.028
    /// above 1 at this amplitude — a sub-pixel-to-1 pt excursion on
    /// typical glyph sizes: subtle, not bouncy).
    public static let pulseOvershoot: Double = 0.05

    /// Center scale for a normalized pulse progress (0...1); a `nil`
    /// progress (settled, or Reduce Motion) is the static final scale 1.
    /// Finite and clamped for any input: out-of-range times clamp to the
    /// endpoints, so the curve can never blow up or go negative.
    public static func scale(progress: Double?) -> Double {
        guard let t = progress else { return 1 }
        let tc = min(max(t, 0), 1)
        let ease = 1 - (1 - tc) * (1 - tc)      // ease-out quad, 0 → 1
        let bump = Foundation.sin(.pi * tc)     // 0 at both ends, 1 mid
        return pulseStartScale
            + (1 - pulseStartScale) * ease
            + pulseOvershoot * bump
    }

    /// The pulse EXCESS weight: 1 at the start of the pass, decaying to
    /// 0 as it settles (a `nil` progress has no excess). The fill alpha
    /// composes as `static + (peak - static) * weight`, so the highlight
    /// emerges emphasized and settles to its quiet static level.
    public static func pulseWeight(progress: Double?) -> Double {
        guard let t = progress else { return 0 }
        let tc = min(max(t, 0), 1)
        let d = 1 - tc
        return d * d
    }
}

/// Pure, clock-injected pulse state for the matching-bracket highlight
/// (the same deterministic pattern as the token `TokenAppearance`).
///
/// All time is caller-supplied (seconds), so the logic is unit-testable
/// without timers or the main thread. A PAIR CHANGE starts exactly one
/// bounded pass; the SAME pair from an incidental redraw, theme switch,
/// caret blink or repeated selection notification does NOT replay;
/// `nil` clears. Reduce Motion installs the final static state
/// immediately (no pass is scheduled, no movement ever happens).
public struct BracketPulseState: Equatable, Sendable {
    /// The currently highlighted pair (nil = no highlight at all).
    public private(set) var pair: BracketPair?
    /// Start time of the in-flight pulse (nil = settled or Reduce
    /// Motion — render the static state).
    public private(set) var pulseStart: TimeInterval?

    public enum Event: Equatable, Sendable {
        /// The pair changed and one bounded pass started (or, under
        /// Reduce Motion, the static state installed immediately).
        case started
        /// The notified pair equals the current one: no pass is
        /// scheduled and no repaint is warranted from this event.
        case unchanged
        /// The highlight cleared.
        case cleared
    }

    public init() {}

    /// Observes a new caret-adjacent pair at `now`. Returns the event so
    /// the caller can decide between starting the tick, doing nothing,
    /// or tearing it down.
    @discardableResult
    public mutating func notify(_ newPair: BracketPair?,
                                now: TimeInterval,
                                reduceMotion: Bool) -> Event {
        guard newPair != pair else { return .unchanged }
        if newPair == nil {
            pair = nil
            pulseStart = nil
            return .cleared
        }
        pair = newPair
        pulseStart = reduceMotion ? nil : now
        return .started
    }

    /// Normalized pulse progress (0...1) at `now`, or nil when settled /
    /// not animating (render the static state).
    public func progress(at now: TimeInterval) -> Double? {
        guard let start = pulseStart else { return nil }
        let t = (now - start) / BracketHighlight.pulseDuration
        if t < 0 { return 0 }
        return min(max(t, 0), 1)
    }

    /// Drops a finished pass. Call once per tick frame.
    public mutating func expire(now: TimeInterval) {
        if let start = pulseStart, now - start >= BracketHighlight.pulseDuration {
            pulseStart = nil
        }
    }

    /// Whether a pulse is still in flight (the tick timer should run).
    public var isAnimating: Bool { pulseStart != nil }
}
