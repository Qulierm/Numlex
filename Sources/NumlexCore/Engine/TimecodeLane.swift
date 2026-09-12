import Foundation

// MARK: - Video timecode lane (temporal Task 4)
//
// A strict lane that owns timecode/frame-shaped lines BEFORE the clock
// and mixed-unit lanes:
//
//   03:10:20:05 at 30 fps + 50 frames        -> 03:10:21:25
//   00:10:20:50 @ 60 fps + 10 minutes        -> 00:20:20:50
//   00:30:10:00 @ 24 fps in frames           -> 43,440 frames
//   43,440 frames @ 24 fps                   -> 00:30:10:00
//   03:10:20:05 at 30 fps + 03:10:20:010     -> 06:20:40:15
//   03:10:20:05 at 12 fps - 00:20:35:00      -> 02:49:45:05
//   30 fps × 3 minutes                       -> 5,400 frames
//   15.6k frames / 24 fps                    -> 650 s
//
// Internal model: a checked non-negative Int64 TOTAL FRAME count plus a
// positive bounded integer frame rate (1...1000). Arithmetic never goes
// through rounded seconds; an overflow is a strict error. Drop-frame
// timecode syntax is deliberately out of scope.
//
// Inside this lane `fps` means frames per second; outside it the
// pre-existing speed alias (`fps` = ft/s) is untouched because the lane
// only claims lines that carry a timecode code or a frame operand.
enum TimecodeLane {

    enum Outcome {
        case result(LineResult)
        case error(String)
        case notMine
    }

    static let maxFPS = 1000
    static let maxFrames = Int64.max

    // MARK: entry

    static func tryLine(_ line: String,
                        context: NumberFormatContext,
                        temporal: TemporalContext,
                        unitContext: UnitContext) -> Outcome {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 160 else { return .notMine }
        let lower = trimmed.lowercased()
        // Fast reject: the lane only owns fps/timecode/frame vocabulary.
        guard lower.contains("fps") || lower.contains("frame")
                || lower.contains(":") && lower.range(of: #"\d+:\d+:\d+:\d+"#,
                                                        options: .regularExpression) != nil else {
            return .notMine
        }
        let extraction = extractRates(trimmed)
        if extraction.malformed {
            return .error("Invalid frame rate")
        }
        var rates = extraction.rates
        var body = extraction.text.trimmingCharacters(in: .whitespaces)
        if body.isEmpty { return .notMine }
        // Shape check: the remaining body must carry a timecode code, a
        // frame operand, or a rate-implied operation.
        let shaped = hasOperand(body) || (!rates.isEmpty && (body.hasPrefix("×") || body.hasPrefix("*")
                                        || body.hasPrefix("/") || body.hasPrefix("÷")
                                        || lower.hasSuffix("fps")))
        guard shaped || !rates.isEmpty else { return .notMine }
        guard !rates.isEmpty else {
            // A timecode/frame line without any rate is a strict error —
            // the plan requires an fps in every timecode/frame operation.
            return .error("Missing frame rate")
        }
        // At most ONE distinct rate may appear.
        if let first = rates.first, rates.contains(where: { $0 != first }) {
            return .error("Conflicting frame rates")
        }
        let fps = rates[0]
        guard fps >= 1, fps <= maxFPS else { return .error("Invalid frame rate") }
        let outcome = parseBody(body, fps: fps, unitContext: unitContext)
        _ = temporal
        _ = context
        return outcome
    }

    // MARK: rate extraction

    /// Removes every `<number> fps` token (with an optional `at`/`@`
    /// prefix) from the line, collecting the rates. A malformed rate
    /// (non-integer or out of range) is reported as `malformed`.
    static func extractRates(_ raw: String) -> (text: String, rates: [Int], malformed: Bool) {
        var out = Array(raw)
        var rates: [Int] = []
        var malformed = false
        var searchStart = 0
        while true {
            guard let idx = findWord(out, "fps", from: searchStart) else { break }
            // A `fpsx`-style word is not `fps`.
            if idx + 3 < out.count, out[idx + 3].isLetter {
                searchStart = idx + 3
                continue
            }
            var dEnd = idx
            while dEnd > 0, out[dEnd - 1] == " " { dEnd -= 1 }
            var dStart = dEnd
            while dStart > 0, out[dStart - 1].isNumber { dStart -= 1 }
            guard dStart < dEnd else {
                out.removeSubrange(idx..<min(idx + 3, out.count))
                searchStart = idx
                continue
            }
            let numberText = String(out[dStart..<dEnd])
            // A decimal rate (`24.5 fps`) is malformed: consume the whole
            // dotted number but never accept it.
            var tokenStart = dStart
            if dStart > 0, out[dStart - 1] == "." {
                malformed = true
                var k = dStart - 1
                while k > 0, out[k - 1].isNumber { k -= 1 }
                tokenStart = k
            } else if let value = Int(numberText), (1...maxFPS).contains(value) {
                rates.append(value)
            } else {
                malformed = true
            }
            // The optional `at`/`@` prefix belongs to the token.
            var start = tokenStart
            var p = tokenStart
            while p > 0, out[p - 1] == " " { p -= 1 }
            if p > 0, out[p - 1] == "@" {
                start = p - 1
            } else if p >= 2, out[p - 1] == "t", out[p - 2] == "a",
                      p - 2 == 0 || out[p - 3] == " " {
                start = p - 2
            }
            let removeEnd = min(idx + 3, out.count)
            guard start < removeEnd else { break }
            out.removeSubrange(start..<removeEnd)
            searchStart = start
        }
        return (String(out), rates, malformed)
    }

    /// Whether the remaining body carries a timecode code or a REAL frame
    /// operand (a number immediately before `frames`/`frame`) — plain
    /// prose merely mentioning the word is never owned.
    static func hasOperand(_ text: String) -> Bool {
        let tokens = text.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        for (i, token) in tokens.enumerated() {
            let clean = token.trimmingCharacters(in: CharacterSet(charactersIn: "+-×*/÷−"))
            guard clean == "frames" || clean == "frame" else { continue }
            guard i > 0, isFrameNumberToken(tokens[i - 1]) else { continue }
            return true
        }
        return text.range(of: #"\d+:\d+:\d+:\d+"#, options: .regularExpression) != nil
    }

    /// A compact frame-number token (`50`, `15.6k`, `43,440`).
    private static func isFrameNumberToken(_ token: String) -> Bool {
        var t = token.trimmingCharacters(in: CharacterSet(charactersIn: "+-"))
        if t.lowercased().hasSuffix("k") { t = String(t.dropLast()) }
        t = t.replacingOccurrences(of: ",", with: "")
        return Double(t)?.isFinite == true
    }

    private static func findWord(_ chars: [Character], _ word: String, from start: Int) -> Int? {
        let w = Array(word)
        guard !w.isEmpty, chars.count >= w.count else { return nil }
        var i = max(0, start)
        while i + w.count <= chars.count {
            var match = true
            for (k, c) in w.enumerated() {
                if String(chars[i + k]).lowercased() != String(c).lowercased() {
                    match = false
                    break
                }
            }
            if match { return i }
            i += 1
        }
        return nil
    }

    // MARK: body parsing

    enum RawOperand {
        case code(h: Int, m: Int, s: Int, f: Int)
        case frames(Int64)
        case duration(Double)
    }

    enum Operand {
        case timecode(Int64)
        case frames(Int64)
        case duration(Double)
    }

    private static func parseBody(_ body: String, fps: Int,
                                  unitContext: UnitContext) -> Outcome {
        var text = body.trimmingCharacters(in: .whitespaces)
        // Conversion suffix.
        var target: String?
        for suffix in [" in frames", " to frames", " in seconds", " to seconds",
                       " in minutes", " to minutes", " in hours", " to hours",
                       " in timecode", " to timecode"] {
            guard text.lowercased().hasSuffix(suffix) else { continue }
            target = String(suffix.split(separator: " ").last!)
            text = String(text.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        if text.isEmpty { return .error("Invalid timecode") }
        // Binary expression?
        if let split = splitBinary(text) {
            let leftText = split.left.trimmingCharacters(in: .whitespaces)
            let rightText = split.right.trimmingCharacters(in: .whitespaces)
            // Rate-involved forms leave one side empty (the rate was
            // extracted from it).
            let left = leftText.isEmpty ? nil : parseRawOperand(leftText, unitContext: unitContext)
            let right = rightText.isEmpty ? nil : parseRawOperand(rightText, unitContext: unitContext)
            guard (leftText.isEmpty || left != nil),
                  (rightText.isEmpty || right != nil) else {
                return .error("Invalid timecode")
            }
            let outcome = applyBinary(op: split.op, left: left, right: right,
                                      fps: fps)
            switch outcome {
            case .error: return outcome
            case .notMine: return .notMine
            case .result(let result):
                switch result {
                case .timecode(let frames, _):
                    return convert(.timecode(frames), target: target, fps: fps)
                case .frameCount(let frames):
                    return convert(.frames(frames), target: target, fps: fps)
                default:
                    return .result(result)
                }
            }
        }
        // Single operand.
        guard let raw = parseRawOperand(text, unitContext: unitContext) else {
            return .error("Invalid timecode")
        }
        switch raw {
        case .code(let h, let m, let s, let f):
            guard let frames = codeFrames(h: h, m: m, s: s, f: f, fps: fps) else {
                return .error("Timecode overflow")
            }
            return convert(.timecode(frames), target: target, fps: fps)
        case .frames(let n):
            // `N frames @ fps` becomes a timecode; a bare frame count with
            // an explicit rate is the idempotent form.
            if target != nil {
                return convert(.frames(n), target: target, fps: fps)
            }
            return .result(.timecode(frames: n, fps: fps))
        case .duration(let seconds):
            // `D + rate` without an operator is not an operation.
            _ = seconds
            return .error("Invalid timecode")
        }
    }

    private static func convert(_ operand: Operand, target: String?,
                                fps: Int) -> Outcome {
        switch (operand, target) {
        case (.timecode(let frames), nil):
            return .result(.timecode(frames: frames, fps: fps))
        case (.timecode(let frames), .some(let t)):
            switch t {
            case "frames": return .result(.frameCount(frames: frames))
            case "seconds": return .result(.number(value: Double(frames) / Double(fps),
                                                   unit: "s", kind: .timecodeSeconds, fraction: nil))
            case "minutes": return .result(.number(value: Double(frames) / Double(fps) / 60,
                                                   unit: "min", kind: .timecodeSeconds, fraction: nil))
            case "hours": return .result(.number(value: Double(frames) / Double(fps) / 3600,
                                                 unit: "h", kind: .timecodeSeconds, fraction: nil))
            case "timecode": return .result(.timecode(frames: frames, fps: fps))
            default: return .error("Invalid timecode")
            }
        case (.frames(let n), nil):
            return .result(.frameCount(frames: n))
        case (.frames(let n), .some(let t)):
            switch t {
            case "frames": return .result(.frameCount(frames: n))
            case "timecode": return .result(.timecode(frames: n, fps: fps))
            case "seconds": return .result(.number(value: Double(n) / Double(fps),
                                                   unit: "s", kind: .timecodeSeconds, fraction: nil))
            case "minutes": return .result(.number(value: Double(n) / Double(fps) / 60,
                                                   unit: "min", kind: .timecodeSeconds, fraction: nil))
            case "hours": return .result(.number(value: Double(n) / Double(fps) / 3600,
                                                 unit: "h", kind: .timecodeSeconds, fraction: nil))
            default: return .error("Invalid timecode")
            }
        case (.duration(let seconds), nil):
            if let frames = framesForDuration(seconds, fps: fps) {
                return .result(.frameCount(frames: frames))
            }
            return .error("Timecode overflow")
        case (.duration(let seconds), .some(let t)):
            switch t {
            case "frames":
                if let frames = framesForDuration(seconds, fps: fps) {
                    return .result(.frameCount(frames: frames))
                }
                return .error("Timecode overflow")
            case "seconds":
                return .result(.number(value: seconds, unit: "s", kind: .timecodeSeconds, fraction: nil))
            default:
                return .error("Invalid timecode")
            }
        }
    }

    private static func applyBinary(op: Character, left: RawOperand?, right: RawOperand?,
                                    fps: Int) -> Outcome {
        // Materialize operands.
        func resolve(_ raw: RawOperand?) -> Operand? {
            guard let raw else { return nil }
            switch raw {
            case .code(let h, let m, let s, let f):
                guard let frames = codeFrames(h: h, m: m, s: s, f: f, fps: fps) else { return nil }
                return .timecode(frames)
            case .frames(let n): return .frames(n)
            case .duration(let d): return .duration(d)
            }
        }
        // Rate-only forms: one side is empty and the rate is the operator's
        // other operand.
        if left == nil || right == nil {
            let operand = left ?? right
            guard let resolved = resolve(operand) else { return .error("Invalid timecode") }
            switch (op, resolved) {
            case ("×", .duration(let seconds)), ("*", .duration(let seconds)):
                guard let frames = framesForDuration(seconds, fps: fps) else {
                    return .error("Timecode overflow")
                }
                return .result(.frameCount(frames: frames))
            case ("×", .frames(let n)), ("*", .frames(let n)):
                return .result(.frameCount(frames: n))
            case ("/", .frames(let n)), ("÷", .frames(let n)):
                // `N frames / rate` is a duration in seconds.
                return .result(.number(value: Double(n) / Double(fps),
                                       unit: "s", kind: .timecodeSeconds, fraction: nil))
            default:
                return .error("Invalid timecode")
            }
        }
        guard let l = resolve(left), let r = resolve(right) else { return .error("Invalid timecode") }
        func frameResult(_ frames: Int64) -> Outcome {
            guard frames >= 0 else { return .error("Timecode cannot be negative") }
            return .result(.timecode(frames: frames, fps: fps))
        }
        func frameCountResult(_ n: Int64) -> Outcome {
            guard n >= 0 else { return .error("Timecode cannot be negative") }
            return .result(.frameCount(frames: n))
        }
        func add(_ a: Int64, _ b: Int64) -> Int64? {
            let (v, overflow) = a.addingReportingOverflow(b)
            return overflow ? nil : v
        }
        func sub(_ a: Int64, _ b: Int64) -> Int64? {
            let (v, overflow) = a.subtractingReportingOverflow(b)
            return overflow ? nil : v
        }
        func mul(_ a: Int64, _ b: Int64) -> Int64? {
            let (v, overflow) = a.multipliedReportingOverflow(by: b)
            return overflow ? nil : v
        }
        func durationFrames(_ seconds: Double) -> Int64? {
            framesForDuration(seconds, fps: fps)
        }
        switch (l, r) {
        case (.timecode(let a), .timecode(let b)):
            if op == "-" {
                guard let v = sub(a, b) else { return .error("Timecode overflow") }
                return frameResult(v)
            }
            guard op == "+" else { return .error("Invalid timecode operation") }
            guard let v = add(a, b) else { return .error("Timecode overflow") }
            return frameResult(v)
        case (.timecode(let a), .frames(let b)):
            if op == "-" {
                guard let v = sub(a, b) else { return .error("Timecode overflow") }
                return frameResult(v)
            }
            guard op == "+" else { return .error("Invalid timecode operation") }
            guard let v = add(a, b) else { return .error("Timecode overflow") }
            return frameResult(v)
        case (.frames(let a), .timecode(let b)):
            guard op == "+" else { return .error("Invalid timecode operation") }
            guard let v = add(a, b) else { return .error("Timecode overflow") }
            return frameResult(v)
        case (.frames(let a), .frames(let b)):
            if op == "-" {
                guard let v = sub(a, b) else { return .error("Timecode overflow") }
                return frameCountResult(v)
            }
            guard op == "+" else { return .error("Invalid timecode operation") }
            guard let v = add(a, b) else { return .error("Timecode overflow") }
            return frameCountResult(v)
        case (.timecode(let a), .duration(let d)):
            guard let df = durationFrames(d) else { return .error("Timecode overflow") }
            if op == "-" {
                guard let v = sub(a, df) else { return .error("Timecode overflow") }
                return frameResult(v)
            }
            guard op == "+" else { return .error("Invalid timecode operation") }
            guard let v = add(a, df) else { return .error("Timecode overflow") }
            return frameResult(v)
        case (.duration(let d), .timecode(let a)):
            guard op == "+" else { return .error("Invalid timecode operation") }
            guard let df = durationFrames(d) else { return .error("Timecode overflow") }
            guard let v = add(df, a) else { return .error("Timecode overflow") }
            return frameResult(v)
        case (.frames(let a), .duration(let d)):
            guard let df = durationFrames(d) else { return .error("Timecode overflow") }
            if op == "-" {
                guard let v = sub(a, df) else { return .error("Timecode overflow") }
                return frameCountResult(v)
            }
            guard op == "+" else { return .error("Invalid timecode operation") }
            guard let v = add(a, df) else { return .error("Timecode overflow") }
            return frameCountResult(v)
        case (.duration(let d), .frames(let a)):
            guard op == "+" else { return .error("Invalid timecode operation") }
            guard let df = durationFrames(d) else { return .error("Timecode overflow") }
            guard let v = add(df, a) else { return .error("Timecode overflow") }
            return frameCountResult(v)
        case (.duration, .duration):
            // `D × rate` / `rate × D` are single-side forms handled above.
            return .error("Invalid timecode operation")
        }
    }

    // MARK: operand parsing

    static func parseRawOperand(_ text: String, unitContext: UnitContext) -> RawOperand? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let code = parseCode(trimmed) { return code }
        if let n = parseFrames(trimmed) { return .frames(n) }
        if let chain = DurationLiteral.parseChain(trimmed, unitContext: unitContext) {
            return .duration(chain.seconds)
        }
        return nil
    }

    /// `hh:mm:ss:ff` (any positive field widths; the frame field may be
    /// `010`). The mm/ss fields are bounded; the frame field is any
    /// non-negative integer and is normalized by carrying.
    static func parseCode(_ text: String) -> RawOperand? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        guard parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isNumber }) }),
              let h = Int(parts[0]), let m = Int(parts[1]),
              let s = Int(parts[2]), let f = Int(parts[3]) else { return nil }
        guard h >= 0, (0...59).contains(m), (0...59).contains(s), f >= 0 else { return nil }
        return .code(h: h, m: m, s: s, f: f)
    }

    /// `<number> frames` / `<number> frame`; the number may carry a `k`
    /// compact suffix (`15.6k frames`). The result must be a whole
    /// number of frames.
    static func parseFrames(_ text: String) -> Int64? {
        let lower = text.lowercased()
        var numberPart: String
        if lower.hasSuffix(" frames") {
            numberPart = String(text.dropLast(" frames".count))
        } else if lower.hasSuffix(" frame") {
            numberPart = String(text.dropLast(" frame".count))
        } else {
            return nil
        }
        numberPart = numberPart.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: "")
        var factor = 1.0
        if numberPart.lowercased().hasSuffix("k") {
            factor = 1000
            numberPart = String(numberPart.dropLast()).trimmingCharacters(in: .whitespaces)
        }
        guard let value = Double(numberPart), value.isFinite, value >= 0 else { return nil }
        let scaled = value * factor
        guard scaled.isFinite, scaled <= 9.007199254740992e15 else { return nil }
        let rounded = scaled.rounded()
        guard abs(scaled - rounded) < 1e-9 else { return nil }
        return Int64(rounded)
    }

    // MARK: arithmetic helpers

    /// The checked total-frame count of a wall code at `fps` (every
    /// multiply/add is overflow-checked; an out-of-range code is nil).
    static func codeFrames(h: Int, m: Int, s: Int, f: Int, fps: Int) -> Int64? {
        guard fps >= 1, h >= 0, m >= 0, s >= 0, f >= 0 else { return nil }
        let (hSeconds, o1) = Int64(h).multipliedReportingOverflow(by: 3600)
        guard !o1 else { return nil }
        let (mSeconds, o2) = Int64(m).multipliedReportingOverflow(by: 60)
        guard !o2 else { return nil }
        let (s1, o3) = hSeconds.addingReportingOverflow(mSeconds)
        guard !o3 else { return nil }
        let (seconds, o4) = s1.addingReportingOverflow(Int64(s))
        guard !o4 else { return nil }
        let (base, o5) = seconds.multipliedReportingOverflow(by: Int64(fps))
        guard !o5 else { return nil }
        let (total, o6) = base.addingReportingOverflow(Int64(f))
        guard !o6, total >= 0 else { return nil }
        return total
    }

    /// The checked frame count of a duration at `fps`.
    static func framesForDuration(_ seconds: Double, fps: Int) -> Int64? {
        guard seconds.isFinite, seconds >= 0, fps >= 1 else { return nil }
        let scaled = (seconds * Double(fps)).rounded()
        guard scaled.isFinite, scaled >= 0, scaled <= 9.007199254740992e15 else { return nil }
        return Int64(scaled)
    }

    /// The shared timecode text: `HH:MM:SS:FF` with zero-padded fields;
    /// the frame field is at least two digits.
    public static func text(frames: Int64, fps: Int) -> String {
        guard fps >= 1 else { return "00:00:00:00" }
        let total = max(frames, 0)
        let ff = total % Int64(fps)
        let totalSeconds = total / Int64(fps)
        let ss = totalSeconds % 60
        let mm = (totalSeconds / 60) % 60
        let hh = totalSeconds / 3600
        let frameWidth = max(2, String(fps - 1).count)
        // Format through Int (the C `%d` width) — never raw Int64 varargs.
        return String(format: "%02d:%02d:%02d:%0\(frameWidth)d",
                      Int(clamping: hh), Int(clamping: mm),
                      Int(clamping: ss), Int(clamping: ff))
    }

    /// The frame count text (`43,440 frames`).
    public static func framesText(_ frames: Int64, context: NumberFormatContext) -> String {
        IntLiteral.formatDecimal(frames, context: context) + " frames"
    }

    // MARK: scanner helpers

    /// The last top-level `+`/`-`/`×`/`*`/`÷`/`/` operator (skipping
    /// colons, which never appear in an operator position).
    private static func splitBinary(_ line: String) -> (left: String, right: String, op: Character)? {
        let chars = Array(line)
        var i = chars.count - 1
        while i >= 0 {
            let c = chars[i]
            if c == "+" || c == "-" || c == "×" || c == "*" || c == "÷" || c == "/" {
                // A `-` directly after a digit is a sign; the operators here
                // always have whitespace on at least one side.
                let hasSpace = (i + 1 < chars.count && chars[i + 1] == " ")
                    || (i > 0 && chars[i - 1] == " ")
                    || (i == 0 && i + 1 < chars.count && chars[i + 1] == " ")
                if hasSpace {
                    let left = String(chars[0..<i])
                    let right = String(chars[(i + 1)...])
                    if left.trimmingCharacters(in: .whitespaces).isEmpty,
                       right.trimmingCharacters(in: .whitespaces).isEmpty {
                        return nil
                    }
                    return (left, right, c)
                }
            }
            i -= 1
        }
        return nil
    }
}
