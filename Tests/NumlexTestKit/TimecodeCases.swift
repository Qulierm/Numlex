import Foundation
import NumlexCore

// MARK: - temporal Task 4: video timecode

private func tcLine(_ line: String,
                    context: NumberFormatContext = .legacy) -> LineResult? {
    var v: [String: Double] = [:]
    return evalLine(line, variables: &v, rates: Rates(), decimalPlaces: 10,
                    now: Date(timeIntervalSince1970: 1_554_112_800),
                    calendar: Calendar(identifier: .gregorian),
                    context: context, unitContext: .builtIns)
}

private func tcText(_ line: String,
                    context: NumberFormatContext = .legacy) -> String? {
    guard let r = tcLine(line, context: context) else { return nil }
    return AnswerDisplay.displayText(for: r, decimalPlaces: 10, context: context)
}

private func expectTC(_ line: String, _ expected: String) throws {
    guard let text = tcText(line) else {
        throw CaseFailure(message: "no timecode text for \(line)", location: "Timecode")
    }
    try expectEqual(text, expected, "\(line)")
}

private func expectTCError(_ line: String) throws {
    guard let r = tcLine(line) else {
        throw CaseFailure(message: "\(line) must evaluate", location: "Timecode")
    }
    guard case .error = r else {
        throw CaseFailure(message: "\(line) must be a strict error, got \(r)",
                          location: "Timecode")
    }
}

public let timecodeCases: [EngineCase] = [

    EngineCase("timecode-official-examples") {
        try expectTC("03:10:20:05 at 30 fps + 50 frames", "03:10:21:25")
        try expectTC("00:10:20:50 @ 60 fps + 10 minutes", "00:20:20:50")
        try expectTC("00:30:10:00 @ 24 fps in frames", "43,440 frames")
        try expectTC("43,440 frames @ 24 fps", "00:30:10:00")
        try expectTC("03:10:20:05 at 30 fps + 03:10:20:010", "06:20:40:15")
        try expectTC("03:10:20:05 at 12 fps - 00:20:35:00", "02:49:45:05")
        try expectTC("30 fps × 3 minutes", "5,400 frames")
        try expectTC("15.6k frames / 24 fps", "650 s")
    },

    EngineCase("timecode-frame-carry-and-normalization") {
        // ff >= fps carries into the next second.
        try expectTC("00:00:00:35 at 30 fps", "00:00:01:05")
        try expectTC("00:00:00:010 at 24 fps", "00:00:00:10")
        try expectTC("00:00:59:59 at 60 fps + 2 frames", "00:01:00:01")
        // The frame field is at least two digits; fps >= 100 widens it.
        try expectTC("00:00:00:5 at 1000 fps", "00:00:00:005")
        // Large codes stay exact (no rounded-second math).
        try expectTC("99:59:59:29 at 30 fps in frames", "10,799,999 frames")
    },

    EngineCase("timecode-strictness") {
        // Missing fps is a strict error for any timecode/frame operation.
        try expectTCError("03:10:20:05 + 50 frames")
        try expectTCError("50 frames + 03:10:20:05")
        try expectTCError("03:10:20:05 in frames")
        // Zero / out-of-range / non-integer fps.
        try expectTCError("03:10:20:05 at 0 fps")
        try expectTCError("03:10:20:05 at 1001 fps")
        try expectTCError("03:10:20:05 at 24.5 fps")
        // Conflicting rates.
        try expectTCError("03:10:20:05 at 30 fps + 00:00:10:00 at 24 fps")
        // Malformed codes.
        try expectTCError("03:70:20:05 at 30 fps")
        try expectTCError("03:10:20 at 30 fps")
        try expectTCError("03:10:20:05:06 at 30 fps")
        // Subtraction below zero is a strict error.
        try expectTCError("00:00:00:10 at 30 fps - 00:00:01:00")
        try expectTCError("0 frames at 24 fps - 1 frames")
        // Int64 overflow is caught, never wrapped.
        try expectTCError("9223372036854775807:00:00:00 at 30 fps")
        try expectTCError("999999999999999 frames × 9223372036854775807")
        // Incompatible operations (frames - timecode).
        try expectTCError("10 frames - 00:00:01:00 at 30 fps")
    },

    EngineCase("timecode-no-theft-and-speed-lane") {
        // The pre-existing speed alias `fps` = ft/s keeps its lane.
        try expectTC("5 m/s to fps", "16.4041994751 ft/s")
        try expectTC("5 fps", "5 ft/s")
        // Plain clocks, dates and durations keep their lanes.
        try expectTC("3:30pm", "3:30 pm")
        try expectTC("2 hours 15 minutes", "2 h 15 min")
        // Prose mentioning frames/fps is not stolen.
        let prose = tcLine("the frame is ready")
        if let prose, case .error = prose {
            throw CaseFailure(message: "prose stays prose", location: "Timecode")
        }
    },

    EngineCase("timecode-totals-menu-and-token-safety") {
        guard case .timecode(let frames, let fps)? = tcLine("03:10:20:05 at 30 fps") else {
            throw CaseFailure(message: "timecode result", location: "Timecode")
        }
        try expectEqual(frames, 342_605, "checked total frames")
        let tc = LineResult.timecode(frames: frames, fps: fps)
        let fc = LineResult.frameCount(frames: 43_440)
        // Never numeric.
        try expect(SheetFooterTotal.contribution(of: tc, isTotalRow: false) == nil,
                   "timecode never enters the footer")
        try expect(SheetFooterTotal.contribution(of: fc, isTotalRow: false) == nil,
                   "frames never enter the footer")
        try expect(InlineTotal.contribution(of: tc, isTotalRow: false) == nil,
                   "timecode never enters inline totals")
        try expect(InlineTotal.contribution(of: fc, isTotalRow: false) == nil,
                   "frames never enter inline totals")
        try expect(!PreviousAnswerPlan.isAnswerable(tc), "no timecode answer chain")
        try expect(!PreviousAnswerPlan.isAnswerable(fc), "no frame answer chain")
        // The lane's `650 s` conversion is a timecode value: it renders as
        // `650 s` yet never enters a total or the numeric chain.
        guard let secsResult = tcLine("15.6k frames / 24 fps"),
              case .number(let secs, let secsUnit, let secsKind, _) = secsResult else {
            throw CaseFailure(message: "timecode seconds conversion", location: "Timecode")
        }
        try expectEqual(secsUnit, "s", "seconds unit")
        try expectClose(secs, 650, 1e-9, "frames / fps")
        try expectEqual(secsKind, .timecodeSeconds, "dedicated temporal kind")
        let secsRow = SheetLine(sourceLineIndex: 0, result: secsResult)
        try expect(SheetFooterTotal.contribution(of: secsRow) == nil,
                   "timecode seconds never enter the footer")
        try expect(InlineTotal.contribution(of: secsRow.result, isTotalRow: false) == nil,
                   "timecode seconds never enter inline totals")
        try expect(!PreviousAnswerPlan.isAnswerable(secsRow.result),
                   "timecode seconds never join the chain")
        // Copy/Delete only; no notation, no rounding.
        try expectEqual(AnswerDisplay.menu(for: tc),
                        AnswerDisplay.Menu(showsActions: true, showsRounding: false),
                        "timecode menu")
        try expectEqual(AnswerDisplay.menu(for: fc),
                        AnswerDisplay.Menu(showsActions: true, showsRounding: false),
                        "frames menu")
        try expect(AnswerDisplay.notationOptions(for: tc) == nil, "no notation")
        try expect(AnswerDisplay.notationOptions(for: fc) == nil, "no notation")
        // Copy == visible.
        try expectEqual(AnswerDisplay.text(for: tc, decimalPlaces: 10, context: .legacy),
                        "03:10:20:05", "timecode copy")
        try expectEqual(AnswerDisplay.text(for: fc, decimalPlaces: 10, context: .legacy),
                        "43,440 frames", "frames copy")
        // A token referencing a timecode source stays safe (broken).
        let marker = "\u{FFFC}"
        let id0 = UUID(), id1 = UUID()
        let content = "03:10:20:05 at 30 fps\n\(marker)"
        let resolved = resolveSheet(content: content, lineIDs: [id0, id1],
                                    references: [AnswerReference(sourceLineID: id0,
                                                                 labelLine: 1, location: 22)],
                                    rates: Rates(), decimalPlaces: 10)
        guard case .timecode = resolved.lines[0].result else {
            throw CaseFailure(message: "the source row is a timecode", location: "Timecode")
        }
        guard case .brokenToken = resolved.lines[1].result else {
            throw CaseFailure(message: "the token stays broken", location: "Timecode")
        }
    },
]
