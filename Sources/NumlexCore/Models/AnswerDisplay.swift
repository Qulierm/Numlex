import Foundation

/// r51: per-answer display preferences (the answer context menu's
/// "Rounding" submenu). Keyed by STABLE line UUID, never by row index,
/// so edits above a line never redirect its override. Presentation-only:
/// the engine keeps evaluating with the global `decimalPlaces` and the
/// override only selects how many decimals the rendered/copied string
/// shows. Not a recalculation mode, not a dependency precision change.
public struct AnswerDisplayPreference: Codable, Equatable, Identifiable, Sendable {
    /// The stable ID of the source logical line (into `Sheet.lineIDs`).
    public var lineID: UUID
    /// Displayed decimal places for this answer's numeric string.
    public var decimalPlaces: Int
    /// r87: optional per-line NOTATION override. `nil` (Default) means
    /// the line follows the GLOBAL notation; the stored value selects
    /// one of the six explicit modes. Pre-r87 records decode to nil.
    public var notation: AnswerNotationOverride?

    public var id: UUID { lineID }

    public init(lineID: UUID, decimalPlaces: Int, notation: AnswerNotationOverride? = nil) {
        self.lineID = lineID
        self.decimalPlaces = decimalPlaces
        self.notation = notation
    }

    /// Tolerant decode: a missing `notation` key (pre-r87) or a
    /// malformed one falls back to nil — the REQUIRED `decimalPlaces`
    /// key still fails the entry if absent (callers use `try?`).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lineID = try c.decode(UUID.self, forKey: .lineID)
        decimalPlaces = try c.decode(Int.self, forKey: .decimalPlaces)
        notation = (try? c.decodeIfPresent(AnswerNotationOverride.self, forKey: .notation)) ?? nil
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(lineID, forKey: .lineID)
        try c.encode(decimalPlaces, forKey: .decimalPlaces)
        try c.encodeIfPresent(notation, forKey: .notation)
    }

    private enum CodingKeys: String, CodingKey {
        case lineID, decimalPlaces, notation
    }
}

public enum AnswerDisplay {
    /// Legal per-answer decimals: 0...10 (the global setting stays
    /// 2...10; an override may show fewer or more trailing decimals of
    /// the available engine value).
    public static let minPlaces = 0
    public static let maxPlaces = 10

    public static func clamped(_ places: Int) -> Int {
        min(max(places, minPlaces), maxPlaces)
    }

    /// Effective decimals for one row: the override wins when present,
    /// otherwise the global setting. Tokens and the summary Total always
    /// use the global value (documented r51 choice: no source-display
    /// side effects, no rounded-display summation).
    public static func effective(defaultPlaces: Int, override: Int?) -> Int {
        override.map(clamped) ?? defaultPlaces
    }

    // MARK: - r54: slider menu presentation (pure)

    /// The slider's INITIAL value for one row: the effective per-answer
    /// precision (override ?? global) clamped to 0...10. Moving the
    /// slider writes an explicit per-line override; there is NO reset
    /// control, so an untouched row keeps inheriting the global
    /// precision until its slider is first moved.
    public static func sliderValue(defaultPlaces: Int, override: Int?) -> Int {
        clamped(effective(defaultPlaces: defaultPlaces, override: override))
    }

    /// The compact visible label next to the slider (`0 dp` ... `10 dp`):
    /// always an integer tick value — a fractional value is never
    /// exposed (the slider is discrete by construction).
    public static func sliderLabel(_ places: Int) -> String {
        "\(clamped(places)) dp"
    }

    /// The localized accessibility/spoken value — the count of decimal
    /// places in the active language (the visible label keeps the
    /// conventional compact `dp` suffix).
    public static func sliderAccessibilityValue(_ places: Int, language: AppLanguage) -> String {
        "\(clamped(places)) \(L10n.t("decimalPlaces", language: language))"
    }

    /// Keeps only preferences whose line still exists, clamps every
    /// value to 0...10, drops duplicates (first wins) and returns the
    /// survivors in CURRENT line order — deterministic, index-free.
    public static func sanitize(_ prefs: [AnswerDisplayPreference],
                                lineIDs: [UUID]) -> [AnswerDisplayPreference] {
        let order = Dictionary(uniqueKeysWithValues: lineIDs.enumerated().map { ($1, $0) })
        var seen = Set<UUID>()
        var kept: [AnswerDisplayPreference] = []
        for p in prefs {
            guard order[p.lineID] != nil, !seen.contains(p.lineID) else { continue }
            seen.insert(p.lineID)
            kept.append(AnswerDisplayPreference(lineID: p.lineID,
                                                decimalPlaces: clamped(p.decimalPlaces),
                                                notation: p.notation))
        }
        return kept.sorted { order[$0.lineID]! < order[$1.lineID]! }
    }

    // MARK: - Shared display string (rendering == Copy Answer)

    /// THE one plain-text rendering of a visible answer row, shared by
    /// `AnswerColumnView.rowView` and Copy Answer so the clipboard always
    /// equals the visible value. Nil = hidden row (blank, prose, title,
    /// generic error): no menu, no copy.
    /// - scalar/variable: the numeric string at the effective decimals;
    /// - unit quantity: `value unit` (currency codes take the money path);
    /// - currency/money: the shared fixed `formatMoney` presentation;
    /// - date: `DateArithmetic.display`; broken token: `Line N`;
    /// - `Rates unavailable`: exactly that text.
    /// r83: the locale-aware string of a SEMANTIC numeric value at the
    /// effective decimals — the ONE shared kinded presentation (answer
    /// copy, token capsule display, token insertion text):
    /// - plain: the number (plus `<unit>` when the unit renders);
    /// - percent: the numeric component ratio × 100 with `%` glued;
    /// - fraction: the reduced rational verbatim (`1/5`);
    /// - multiplier: the factor with `x` glued (`1.5x`).
    /// A clock value's text (the ONE presentation used by the visible row,
    /// the clipboard and the tokens).
    public static func clockText(hour: Int, minute: Int, second: Int,
                                 hasSeconds: Bool, dayOffset: Int,
                                 context: NumberFormatContext) -> String {
        let style = ClockStyle.forContext(context)
        let calendar = Calendar(identifier: .gregorian)
        let temporal = TemporalContext(now: Date(), calendar: calendar,
                                       timeZone: .current, clockStyle: style)
        return temporal.clockText(hour: hour, minute: minute, second: second,
                                  hasSeconds: hasSeconds, dayOffset: dayOffset)
    }

    public static func laptimeText(_ seconds: Double) -> String {
        TemporalContext.laptimeText(seconds: seconds)
    }

    /// temporal Task 4: the shared `HH:MM:SS:FF` timecode text.
    public static func timecodeText(frames: Int64, fps: Int) -> String {
        TimecodeLane.text(frames: frames, fps: fps)
    }

    /// temporal Task 4: the shared grouped frame-count text.
    public static func framesText(_ frames: Int64,
                                  context: NumberFormatContext) -> String {
        TimecodeLane.framesText(frames, context: context)
    }

    /// temporal Task 2: the ONE date-time rendering, shared by the visible
    /// row, Copy Answer and tests. `iso` selects the canonical
    /// `yyyy-MM-dd'T'HH:mm:ssXXX` form (with the source/local offset);
    /// otherwise the regional 12/24-hour clock style is prepended to the
    /// deterministic English date (`Apr 1, 2019 3:30 pm`).
    public static func dateTimeText(year: Int, month: Int, day: Int,
                                    hour: Int, minute: Int, second: Int,
                                    hasSeconds: Bool, utcOffsetSeconds: Int,
                                    iso: Bool,
                                    context: NumberFormatContext) -> String {
        if iso {
            let offset: String
            if utcOffsetSeconds == 0 {
                offset = "Z"
            } else {
                let sign = utcOffsetSeconds < 0 ? "-" : "+"
                let a = abs(utcOffsetSeconds)
                offset = "\(sign)\(String(format: "%02d", a / 3600)):\(String(format: "%02d", (a % 3600) / 60))"
            }
            return String(format: "%04d-%02d-%02dT%02d:%02d:%02d%@",
                          year, month, day, hour, minute, second, offset)
        }
        let clock: String
        switch ClockStyle.forContext(context) {
        case .twelveHour:
            let displayHour = hour % 12 == 0 ? 12 : hour % 12
            let suffix = hour < 12 ? "am" : "pm"
            var text = "\(displayHour):\(String(format: "%02d", minute))"
            if hasSeconds { text += ":\(String(format: "%02d", second))" }
            clock = text + " \(suffix)"
        case .twentyFourHour:
            var text = String(format: "%02d:%02d", hour, minute)
            if hasSeconds { text += String(format: ":%02d", second) }
            clock = text
        }
        return "\(DateArithmetic.display(year: year, month: month, day: day, showYear: true)) \(clock)"
    }

    /// The plain numeric presentation of an epoch row.
    public static func timestampText(_ seconds: Double, decimalPlaces: Int,
                                     context: NumberFormatContext) -> String? {
        guard seconds.isFinite else { return nil }
        return formatDisplayValue(seconds, decimalPlaces: decimalPlaces,
                                  context: context.withoutCompactNotation)
    }

    /// temporal Task 3: the ONE timespan text for a quantity, or nil when
    /// the unit is not a time-dimension quantity (the caller falls back to
    /// Automatic deterministically).
    public static func timespanText(value: Double, unit: String?,
                                    decimalPlaces: Int,
                                    context: NumberFormatContext) -> String? {
        guard let unit else { return nil }
        return TimespanPresentation.text(value: value, unitLabel: unit,
                                         decimalPlaces: decimalPlaces,
                                         context: context)
    }

    public static func formatKinded(_ value: Double, unit: String?,
                                    kind: NumericKind, fraction: Rational?,
                                    decimalPlaces: Int,
                                    context: NumberFormatContext) -> String {
        switch kind {
        case .plain, .timecodeSeconds:
            let s = formatDisplayValue(value, decimalPlaces: decimalPlaces,
                                       context: context.withoutCompactNotation)
            if let u = unit { return "\(s) \(u)" }
            return s
        case .percent:
            let s = formatDisplayValue(value * 100, decimalPlaces: decimalPlaces,
                                       context: context.withoutCompactNotation)
            return "\(s)%"
        case .fraction:
            if let r = fraction {
                return "\(r.numerator)/\(r.denominator)"
            }
            return formatDisplayValue(value, decimalPlaces: decimalPlaces,
                                      context: context.withoutCompactNotation)
        case .multiplier:
            let s = formatDisplayValue(value, decimalPlaces: decimalPlaces,
                                       context: context.withoutCompactNotation)
            return "\(s)x"
        case .duration:
            // The ONE natural decomposition, shared with Copy and tokens.
            if let natural = DurationPresentation.naturalText(value: value, unit: unit,
                                                              kind: kind,
                                                              decimalPlaces: decimalPlaces,
                                                              context: context) {
                return natural
            }
            let s = formatDisplayValue(value, decimalPlaces: decimalPlaces,
                                       context: context.withoutCompactNotation)
            if let u = unit { return "\(s) \(u)" }
            return s
        case .timespan:
            // The ONE timespan decomposition; a non-time unit falls back
            // to the automatic plain shape (never blank, never an error).
            if let span = timespanText(value: value, unit: unit,
                                       decimalPlaces: decimalPlaces,
                                       context: context) {
                return span
            }
            let s = formatDisplayValue(value, decimalPlaces: decimalPlaces,
                                       context: context.withoutCompactNotation)
            if let u = unit { return "\(s) \(u)" }
            return s
        }
    }

    public static func text(for result: LineResult, decimalPlaces: Int) -> String? {
        text(for: result, decimalPlaces: decimalPlaces, context: .legacy)
    }

    /// r73: the context-aware copy string. Plain scalars copy the
    /// FULL-PRECISION (non-compact) value in the context's separators
    /// — the display row may compact (100k) but the clipboard keeps
    /// the exact 100,000 shape; money keeps the shared money
    /// presentation.
    ///
    /// r87: `notation`/`prefs` are the EFFECTIVE row presentation
    /// (per-line override ?? global; defaults reproduce the pre-r87
    /// automatic strings byte-for-byte).
    public static func text(for result: LineResult, decimalPlaces: Int,
                             context: NumberFormatContext,
                             notation: NumberNotation? = nil,
                             prefs: NumberPresentationPreferences = .defaults) -> String? {
        let eff = notation ?? prefs.notation
        switch result {
        case .blank, .skip, .title:
            return nil
        case .clock(let h, let m, let sec, let hasSeconds, let dayOffset):
            // One presentation for the visible row, the clipboard and the
            // tokens; the clock style comes from the number context.
            return clockText(hour: h, minute: m, second: sec,
                             hasSeconds: hasSeconds, dayOffset: dayOffset,
                             context: context)
        case .laptime(let seconds):
            return laptimeText(seconds)
        case .number(let v, let unit, let kind, let fraction):
            if let u = unit, isCurrencyCode(u) {
                return NumberPresentation.formatMoney(v, code: u,
                                                       notation: eff,
                                                       prefs: prefs, context: context)
            }
            if kind == .duration || kind == .timespan {
                // Duration/timespan presentation is semantic, not a
                // notation: the copy is byte-identical to the visible row.
                return formatKinded(v, unit: unit, kind: kind, fraction: fraction,
                                    decimalPlaces: decimalPlaces, context: context)
            }
            // temporal Task 3: the Timespan NOTATION applies only to
            // time-dimension quantities; every other number falls back to
            // the automatic formatter.
            if eff == .timespan, let u = unit,
               let span = TimespanPresentation.text(value: v, unitLabel: u,
                                                    decimalPlaces: decimalPlaces,
                                                    context: context) {
                return span
            }
            let eff = eff == .timespan ? .automatic : eff
            // r87: automatic keeps the ONE shared kinded presentation
            // (percent × 100 + `%`, the exact rational verbatim,
            // multiplier + `x`) on the full-precision copy shape;
            // non-automatic notations shape the numeric component and
            // keep the kind suffix.
            let copyContext: NumberFormatContext =
                eff == .automatic ? context.withoutCompactNotation : context
            if eff == .automatic {
                return formatKinded(v, unit: unit, kind: kind, fraction: fraction,
                                    decimalPlaces: decimalPlaces, context: copyContext)
            }
            if kind == .fraction {
                // The exact reduced rational stays verbatim in every
                // notation (the same contract the menu descriptor
                // makes: semantic fractions are never re-notated).
                if let r = fraction {
                    return r.denominator == 0
                        ? "0"
                        : NumberPresentation.fractionText((n: r.numerator, d: r.denominator))
                }
                return NumberPresentation.format(v, category: .plain, notation: eff,
                                                 precision: decimalPlaces, prefs: prefs,
                                                 context: copyContext)
            }
            let s: String
            switch kind {
            case .percent:
                s = NumberPresentation.format(v * 100, category: .plain,
                                              notation: eff, precision: decimalPlaces,
                                              prefs: prefs, context: copyContext) + "%"
            case .multiplier:
                s = NumberPresentation.format(v, category: .plain,
                                              notation: eff, precision: decimalPlaces,
                                              prefs: prefs, context: copyContext) + "x"
            case .plain, .fraction, .duration, .timespan, .timecodeSeconds:
                let exact = (v.truncatingRemainder(dividingBy: 1) == 0
                             && abs(v) <= 9.007199254740992e15) ? Int64(v) : nil
                s = NumberPresentation.format(v, int64: exact,
                                              category: exact != nil ? .int64 : .plain,
                                              notation: eff, precision: decimalPlaces,
                                              prefs: prefs, context: copyContext)
            }
            if let u = unit { return "\(s) \(u)" }
            return s
        case .boolean(let b):
            // r82: booleans copy exactly as their lowercase word.
            return b ? "true" : "false"
        case .integer(let v, let radix):
            // r85: the EXACT base text — no decimal rounding, no
            // compact notation. Decimal rows take the row notation
            // (r87); radix rows are the canonical compact form.
            if radix == 10 {
                return NumberPresentation.formatInt64(v, notation: eff == .automatic ? .automatic : eff,
                                                      precision: decimalPlaces, prefs: prefs,
                                                      context: context)
            }
            return IntLiteral.format(v, radix: radix)
        case .variableInt(_, let v, let radix):
            // Negative values present in decimal (signed-magnitude).
            if radix == 10 || v < 0 {
                return NumberPresentation.formatInt64(v, notation: eff == .automatic ? .automatic : eff,
                                                      precision: decimalPlaces, prefs: prefs,
                                                      context: context)
            }
            return IntLiteral.format(v, radix: radix)
        case .location(_, _, let c):
            // r85: the retypeable coordinate pair — dot-decimal modes
            // separate the pair with a comma, decimal-comma modes with
            // `;` so the copied pair is retypeable in every mode.
            return GeoPresentation.coordinateText(c, context: context)
        case .dms(let p):
            return DMSTools.display(p, context: context)
        case .variable(_, let v, let kind, let fraction):
            // r83: an assigned value keeps its semantic kind on display
            // (`x = 10% + 20%` shows `30%`).
            if kind == .duration {
                // A duration-typed variable carries its presentation marker
                // through assignment; the unit lives on the ENV entry, so
                // the row is shown from the stored quantity (the view path
                // passes the unit) — with no unit here, fall back to the
                // plain shape.
                return formatKinded(v, unit: nil, kind: .plain, fraction: fraction,
                                    decimalPlaces: decimalPlaces, context: context)
            }
            if kind == .timespan {
                // A timespan-typed variable is unitless here; the plain
                // automatic shape is the deterministic fallback.
                return formatKinded(v, unit: nil, kind: .plain, fraction: fraction,
                                    decimalPlaces: decimalPlaces, context: context)
            }
            let eff = eff == .timespan ? .automatic : eff
            let copyContext: NumberFormatContext =
                eff == .automatic ? context.withoutCompactNotation : context
            if eff == .automatic {
                return formatKinded(v, unit: nil, kind: kind, fraction: fraction,
                                    decimalPlaces: decimalPlaces, context: copyContext)
            }
            if kind == .fraction {
                if let r = fraction {
                    return r.denominator == 0
                        ? "0"
                        : NumberPresentation.fractionText((n: r.numerator, d: r.denominator))
                }
                return NumberPresentation.format(v, category: .plain, notation: eff,
                                                 precision: decimalPlaces, prefs: prefs,
                                                 context: copyContext)
            }
            let s: String
            switch kind {
            case .percent:
                s = NumberPresentation.format(v * 100, category: .plain,
                                              notation: eff, precision: decimalPlaces,
                                              prefs: prefs, context: copyContext) + "%"
            case .multiplier:
                s = NumberPresentation.format(v, category: .plain,
                                              notation: eff, precision: decimalPlaces,
                                              prefs: prefs, context: copyContext) + "x"
            case .plain, .fraction, .duration, .timespan, .timecodeSeconds:
                s = NumberPresentation.format(v, category: .plain,
                                              notation: eff, precision: decimalPlaces,
                                              prefs: prefs, context: copyContext)
            }
            return s
        case .money(let v, let code):
            return NumberPresentation.formatMoney(v, code: code, notation: eff,
                                                  prefs: prefs, context: context)
        case .date(let y, let m, let d, let showYear):
            return DateArithmetic.display(year: y, month: m, day: d, showYear: showYear)
        case .dateTime(let y, let m, let d, let h, let min, let s, let hasSeconds, let offset, let iso):
            return dateTimeText(year: y, month: m, day: d, hour: h, minute: min, second: s,
                                hasSeconds: hasSeconds, utcOffsetSeconds: offset,
                                iso: iso, context: context)
        case .timestamp(let seconds):
            return timestampText(seconds, decimalPlaces: decimalPlaces, context: context)
        case .timecode(let frames, let fps):
            return TimecodeLane.text(frames: frames, fps: fps)
        case .frameCount(let frames):
            return TimecodeLane.framesText(frames, context: context)
        case .brokenToken(let line):
            return "Line \(line)"
        case .error(let msg):
            // r55: `Weather unavailable` renders in the view (localized)
            // but is never copied — like other quiet errors it has no
            // clipboard text.
            if WeatherQuery.isUnavailableMessage(msg) || GeoQueryParse.isUnavailableMessage(msg) {
                return nil
            }
            return msg == "Rates unavailable" ? "Rates unavailable" : nil
        }
    }

    /// r87: the DISPLAY string for one row. Identical to the copy
    /// string EXCEPT the automatic default, where the display row may
    /// compact while the copy keeps full precision (the R73
    /// exception). Non-automatic notations share one string.
    public static func displayText(for result: LineResult, decimalPlaces: Int,
                                   context: NumberFormatContext,
                                   notation: NumberNotation? = nil,
                                   prefs: NumberPresentationPreferences = .defaults) -> String? {
        let eff = notation ?? prefs.notation
        if eff != .automatic { return text(for: result, decimalPlaces: decimalPlaces,
                                           context: context, notation: eff, prefs: prefs) }
        // Automatic: the pre-r87 row shapes (plain unit values display
        // in the raw — compact-capable — context; the unitless kinded
        // shapes use the non-compact shared string).
        switch result {
        case .number(let v, let unit, let kind, _):
            if let u = unit, isCurrencyCode(u) {
                return formatMoney(v, code: u, context: context)
            }
            if kind == .duration || kind == .timespan {
                return formatKinded(v, unit: unit, kind: kind,
                                    fraction: nil, decimalPlaces: decimalPlaces,
                                    context: context)
            }
            if kind == .plain {
                // The R73 exception: a unitless plain row DISPLAYS in
                // the raw (compact-capable) context while the copy
                // keeps full precision; unit rows display raw too.
                let s = formatDisplayValue(v, decimalPlaces: decimalPlaces,
                                           context: context)
                if let u = unit { return "\(s) \(u)" }
                return s
            }
            return text(for: result, decimalPlaces: decimalPlaces, context: context,
                        notation: eff, prefs: prefs)
        case .money(let v, let code):
            return formatMoney(v, code: code, context: context)
        default:
            return text(for: result, decimalPlaces: decimalPlaces, context: context,
                        notation: eff, prefs: prefs)
        }
    }

    // MARK: - r87: Number Format menu eligibility (pure descriptor)

    /// Which NOTATION choices a row's menu offers. nil = no Number
    /// Format submenu (dates, booleans, coordinates, DMS, errors,
    /// the semantic fraction kind, broken tokens). `allowsFraction`
    /// marks fraction-eligible rows (plain non-money values — money
    /// never fractionizes); Custom's enabled state is computed by the
    /// menu builder from the global pattern's validity.
    public struct NotationOptions: Equatable, Sendable {
        public var allowsFraction: Bool
        public init(allowsFraction: Bool) { self.allowsFraction = allowsFraction }
    }

    public static func notationOptions(for result: LineResult) -> NotationOptions? {
        switch result {
        case .clock, .laptime:
            // A temporal value has no number notation to choose.
            return nil
        case .blank, .skip, .title, .brokenToken, .date, .location, .dms, .error:
            return nil
        case .dateTime, .timestamp, .timecode, .frameCount:
            // temporal Task 2/4: date-time/epoch/timecode rows have no
            // number notation.
            return nil
        case .boolean:
            // r82: true/false has nothing to re-notation.
            return nil
        case .number(_, let unit, let kind, _):
            if let u = unit, isCurrencyCode(u) {
                return NotationOptions(allowsFraction: false)
            }
            switch kind {
            case .fraction:
                return nil  // the exact reduced rational stays verbatim
            case .duration:
                // A natural duration has component semantics; no notation,
                // no fraction, no compact/scientific form. (The GLOBAL
                // Timespan notation still applies to it through the row
                // presentation path; the per-answer menu stays absent,
                // exactly as before Task 3.)
                return nil
            case .timespan:
                // Already the timespan shape: nothing to re-notation.
                return nil
            case .timecodeSeconds:
                // A timecode-lane duration has no number notation.
                return nil
            case .plain, .percent, .multiplier:
                return NotationOptions(allowsFraction: kind == .plain)
            }
        case .variable(_, _, let kind, _):
            switch kind {
            case .fraction:
                return nil
            case .duration:
                return nil
            case .timespan, .timecodeSeconds:
                return nil
            case .plain, .percent, .multiplier:
                return NotationOptions(allowsFraction: kind == .plain)
            }
        case .integer(_, let radix), .variableInt(_, _, let radix):
            // Exact Int64: radix rows stay canonical; decimal-radix
            // (and negative, which presents decimal) rows take any
            // notation through the exact digit paths.
            return radix == 10 ? NotationOptions(allowsFraction: true) : nil
        case .money:
            return NotationOptions(allowsFraction: false)
        }
    }

    // MARK: - Context menu eligibility (pure descriptor)

    /// Which answer-specific actions a row offers. The menu appears only
    /// for rows with visible/meaningful content; Delete is available for
    /// every visible row, Copy for the same set, Rounding only for plain
    /// numeric scalar/variable rows (money keeps its fixed presentation,
    /// dates/broken/rates have no decimals to choose).
    public struct Menu: Equatable, Sendable {
        /// Show Copy Answer + Delete Line.
        public var showsActions: Bool
        /// Show the Rounding submenu (implies showsActions).
        public var showsRounding: Bool
        public init(showsActions: Bool, showsRounding: Bool) {
            self.showsActions = showsActions
            self.showsRounding = showsRounding
        }
    }

    public static func menu(for result: LineResult) -> Menu? {
        switch result {
        case .blank, .skip, .title:
            return nil
        case .clock, .laptime:
            // Copy Answer and Delete Line only: a clock has no decimals to
            // round and no notation to choose.
            return Menu(showsActions: true, showsRounding: false)
        case .timecode, .frameCount:
            // temporal Task 4: timecode/frame rows are Copy/Delete only.
            return Menu(showsActions: true, showsRounding: false)
        case .error(let msg):
            // r55: weather-unavailable rows offer no menu at all (no
            // Copy, no rounding) — quiet and secondary by design.
            if WeatherQuery.isUnavailableMessage(msg) { return nil }
            return msg == "Rates unavailable"
                ? Menu(showsActions: true, showsRounding: false)
                : nil
        case .number(_, let unit, let kind, _):
            if let u = unit, isCurrencyCode(u) {
                return Menu(showsActions: true, showsRounding: false)
            }
            switch kind {
            case .plain, .percent, .multiplier:
                // r83: percent and multiplier answers round their
                // DISPLAYED numeric component (the percent number or
                // the factor) — the same 0...10 slider as plain numbers.
                return Menu(showsActions: true, showsRounding: true)
            case .fraction:
                // r83: a fraction is Copy/Delete only — a reduced
                // rational has no decimals to choose.
                return Menu(showsActions: true, showsRounding: false)
            case .duration, .timespan, .timecodeSeconds:
                // A natural duration/timespan/timecode-seconds value has
                // component semantics, not a decimal count: Copy and
                // Delete only.
                return Menu(showsActions: true, showsRounding: false)
            }
        case .variable(_, _, let kind, _):
            switch kind {
            case .plain, .percent, .multiplier:
                return Menu(showsActions: true, showsRounding: true)
            case .fraction:
                return Menu(showsActions: true, showsRounding: false)
            case .duration, .timespan, .timecodeSeconds:
                return Menu(showsActions: true, showsRounding: false)
            }
        case .boolean:
            // r82: booleans offer Copy Answer + Delete Line only —
            // there is nothing to round on a true/false.
            return Menu(showsActions: true, showsRounding: false)
        case .integer, .variableInt:
            // r85: base answers are Copy/Delete only — an exact
            // Int64 has no decimals to round.
            return Menu(showsActions: true, showsRounding: false)
        case .location, .dms:
            // r85: coordinate and DMS answers are Copy/Delete only.
            return Menu(showsActions: true, showsRounding: false)
        case .money, .date, .brokenToken, .dateTime, .timestamp,
             .timecode, .frameCount:
            return Menu(showsActions: true, showsRounding: false)
        }
    }

    // MARK: - Pure logical-line deletion plan

    /// One deleted logical line as an exact UTF-16 plan: the new content,
    /// the announced `NotebookEdit` (nil range only when the content is
    /// already empty) and the caret landing at the deletion start. The
    /// newline goes with the line — a non-last line deletes its trailing
    /// newline, the last line its preceding one, the sole line the whole
    /// content. The caller reconciles line IDs/references through
    /// `LineIdentity.reconcile` with this exact edit, so survivors keep
    /// stable IDs, markers shift exactly, and tokens on the deleted line
    /// break naturally.
    public struct LineDeletion: Equatable, Sendable {
        public var content: String
        public var edit: NotebookEdit?
        /// UTF-16 offset of the deletion start (= caret landing, caller
        /// clamps to the final content).
        public var caret: Int
    }

    public static func deleteLinePlan(content: String, lineIndex: Int) -> LineDeletion? {
        let lines = content.components(separatedBy: "\n")
        guard lines.indices.contains(lineIndex) else { return nil }
        let ns = content as NSString
        // UTF-16 start offset of every logical line.
        var starts: [Int] = []
        var off = 0
        for (i, ln) in lines.enumerated() {
            starts.append(off)
            off += (ln as NSString).length + (i < lines.count - 1 ? 1 : 0)
        }
        let start = starts[lineIndex]
        let lineLen = (lines[lineIndex] as NSString).length
        let range: NSRange
        if lines.count == 1 {
            range = NSRange(location: 0, length: ns.length)
        } else if lineIndex < lines.count - 1 {
            // Non-last line: the line plus its following newline.
            range = NSRange(location: start, length: lineLen + 1)
        } else {
            // Last line: the preceding newline plus the line.
            range = NSRange(location: start - 1, length: lineLen + 1)
        }
        let edit = NotebookEdit(range: range, replacement: "")
        let newContent = ns.replacingCharacters(in: range, with: "")
        return LineDeletion(content: newContent, edit: edit, caret: range.location)
    }
}
