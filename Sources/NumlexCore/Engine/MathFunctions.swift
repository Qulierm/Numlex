import Foundation

/// r47: the ONE central registry and evaluator for built-in math
/// functions. Every scalar route (the shared expression parser, the
/// strict named/constant core, the unitless token route) resolves names
/// and arities against this table — there is no second name/arity/domain
/// list anywhere else in the engine.
///
/// Grammar (r47): a function call is an identifier in LOWER-CASE-CANONICAL
/// name followed by optional whitespace and `(`, with comma-separated
/// full expressions as arguments. Calls participate anywhere a primary
/// participates: literals, parentheses, unary signs, `^`, postfix `%`
/// and `of` compose with them unchanged. A builtin activates ONLY in
/// call position: a variable or constant named `sum` is still a valid
/// identifier in every non-call position (`sum + 1`), and nothing is
/// globally reserved or invalidated. In `sum(...)`, the builtin takes
/// precedence over a same-named variable/constant at the call head.
///
/// Any function-SHAPED input (identifier + optional whitespace + `(`)
/// is STRICT: an unknown name, a bad arity, a bad comma, a missing
/// close parenthesis or a domain failure is a deterministic error — it
/// never degrades to a parenthesized operand and never mutates the
/// environment.
public enum MathFunctions {

    // MARK: Registry (single source of truth)

    /// The builtin table: lowercased name plus the arity bounds.
    /// `maxArity == .max` marks a variadic.
    static let table: [(name: String, minArity: Int, maxArity: Int)] = [
        ("sqrt", 1, 1),
        ("abs", 1, 1),
        ("round", 1, 2),
        ("min", 1, .max),
        ("max", 1, .max),
        ("sum", 1, .max),
        ("average", 1, .max),
        ("pow", 2, 2),
        ("ln", 1, 1),
        ("log", 1, 2),
        ("log10", 1, 1),
        ("sin", 1, 1),
        ("cos", 1, 1),
        ("tan", 1, 1),
        ("asin", 1, 1),
        ("acos", 1, 1),
        ("atan", 1, 1),
        ("radians", 1, 1),
        ("degrees", 1, 1),
    ]

    /// Every known builtin name (lowercased). Membership is the shared
    /// "is this a function" predicate used by the parser, the strict
    /// core, the residual guard, the constant resolver and the
    /// syntax classifier.
    public static let knownNames: Set<String> = Set(table.map(\.name))

    /// Case-insensitive builtin test.
    public static func isKnown(_ name: String) -> Bool {
        knownNames.contains(name.lowercased())
    }

    /// The arity bounds of a known name.
    public static func arity(_ name: String) -> (min: Int, max: Int)? {
        let key = name.lowercased()
        for row in table where row.name == key {
            return (row.minArity, row.maxArity)
        }
        return nil
    }

    // MARK: Errors

    /// Deterministic function failures. Messages are stable: no
    /// trapping, NaN or infinity ever escapes this API.
    public enum MathFunctionError: Error, LocalizedError {
        /// The argument count is outside the builtin's arity bounds.
        case arity(name: String, got: Int, min: Int, max: Int)
        /// A value-domain violation (`ln` of a non-positive, `asin`
        /// out of [-1, 1], a bad `log` base, a non-integer `round`
        /// digit count outside -15...15).
        case domain(name: String, detail: String)
        /// A non-finite intermediate or result (overflow, `10^400`).
        case nonFinite(name: String)

        public var errorDescription: String? {
            switch self {
            case .arity(let name, let got, let min, let max):
                if min == max {
                    return "\(name) expects exactly \(min) argument (got \(got))"
                }
                if max == .max {
                    return "\(name) expects at least \(min) arguments (got \(got))"
                }
                return "\(name) expects \(min)...\(max) arguments (got \(got))"
            case .domain(let name, let detail):
                return "\(name): \(detail)"
            case .nonFinite(let name):
                return "\(name): result is not finite"
            }
        }
    }

    // MARK: Evaluation

    /// Evaluates a known builtin on FINITE scalar arguments and returns
    /// a finite result, or throws a deterministic `MathFunctionError`.
    /// Arity is enforced here as a last line (the parser already
    /// rejects out-of-bounds argument counts at parse time).
    ///
    /// Semantics (all finite Double, radians for the trig family):
    /// - `sqrt(x)`: x >= 0.
    /// - `abs(x)`: any finite x.
    /// - `round(x)` / `round(x, d)`: d a finite integer in -15...15;
    ///   ties round AWAY FROM ZERO (Swift `toNearestOrAwayFromZero`);
    ///   stable scaling, overflow rejected.
    /// - `min`/`max`/`sum`/`average`: variadic (>= 1); `average` uses a
    ///   shifted partial sum so a finite mean is never lost to a naive
    ///   intermediate overflow.
    /// - `pow(b, e)`: exactly the shared `^` contract (finite result).
    /// - `ln(x)`: x > 0. `log(x)`: log base 10. `log10(x)`: base 10.
    ///   `log(x, b)`: b > 0, b != 1, x > 0.
    /// - `sin`/`cos`/`tan`: radians. `asin`/`acos`: |x| <= 1.
    ///   `atan`: any finite. `radians(d)`: d * pi/180.
    ///   `degrees(r)`: r * 180/pi.
    public static func evaluate(_ name: String, args: [Double]) throws -> Double {
        let key = name.lowercased()
        guard let (min, max) = arity(key) else {
            // Unreachable through the parser (unknown names fail at
            // parse time); deterministic anyway.
            throw MathFunctionError.domain(name: name, detail: "unknown function")
        }
        guard args.count >= min, args.count <= max else {
            throw MathFunctionError.arity(name: key, got: args.count, min: min, max: max)
        }
        for a in args where !a.isFinite {
            throw MathFunctionError.nonFinite(name: key)
        }
        switch key {
        case "sqrt":
            let x = args[0]
            guard x >= 0 else { throw MathFunctionError.domain(name: key, detail: "argument must be >= 0") }
            return try checked(key) { sqrt(x) }
        case "abs":
            return try checked(key) { abs(args[0]) }
        case "round":
            let x = args[0]
            let d: Double
            if args.count == 1 {
                d = 0
            } else {
                let raw = args[1]
                guard raw.truncatingRemainder(dividingBy: 1) == 0,
                      let dInt = Int(exactly: raw),
                      (-15...15).contains(dInt) else {
                    throw MathFunctionError.domain(name: key, detail: "digits must be an integer in -15...15")
                }
                d = Double(dInt)
            }
            let scale = pow(10, d)
            let shifted = x * scale
            guard shifted.isFinite else { throw MathFunctionError.nonFinite(name: key) }
            let rounded = shifted.rounded(.toNearestOrAwayFromZero)
            let v = rounded / scale
            guard v.isFinite else { throw MathFunctionError.nonFinite(name: key) }
            return v
        case "min":
            return args.reduce(args[0]) { Swift.min($0, $1) }
        case "max":
            return args.reduce(args[0]) { Swift.max($0, $1) }
        case "sum":
            var total = 0.0
            for a in args {
                total += a
                guard total.isFinite else { throw MathFunctionError.nonFinite(name: key) }
            }
            return total
        case "average":
            return try stableAverage(args)
        case "pow":
            let v = pow(args[0], args[1])
            guard v.isFinite else { throw MathFunctionError.nonFinite(name: key) }
            return v
        case "ln":
            let x = args[0]
            guard x > 0 else { throw MathFunctionError.domain(name: key, detail: "argument must be > 0") }
            return try checked(key) { log(x) }
        case "log":
            let x = args[0]
            guard x > 0 else { throw MathFunctionError.domain(name: key, detail: "argument must be > 0") }
            if args.count == 1 {
                return try checked(key) { log10(x) }
            }
            let b = args[1]
            guard b > 0, b != 1 else { throw MathFunctionError.domain(name: key, detail: "base must be > 0 and != 1") }
            return try checked(key) { log(x) / log(b) }
        case "log10":
            let x = args[0]
            guard x > 0 else { throw MathFunctionError.domain(name: key, detail: "argument must be > 0") }
            return try checked(key) { log10(x) }
        case "sin":
            return try checked(key) { sin(args[0]) }
        case "cos":
            return try checked(key) { cos(args[0]) }
        case "tan":
            return try checked(key) { tan(args[0]) }
        case "asin":
            let x = args[0]
            guard x >= -1, x <= 1 else { throw MathFunctionError.domain(name: key, detail: "argument must be in -1...1") }
            return try checked(key) { asin(x) }
        case "acos":
            let x = args[0]
            guard x >= -1, x <= 1 else { throw MathFunctionError.domain(name: key, detail: "argument must be in -1...1") }
            return try checked(key) { acos(x) }
        case "atan":
            return try checked(key) { atan(args[0]) }
        case "radians":
            return try checked(key) { args[0] * Double.pi / 180 }
        case "degrees":
            return try checked(key) { args[0] * 180 / Double.pi }
        default:
            throw MathFunctionError.domain(name: name, detail: "unknown function")
        }
    }

    /// `checked`: the finiteness contract for single-expression ops.
    private static func checked(_ name: String, _ body: () -> Double) throws -> Double {
        let v = body()
        guard v.isFinite else { throw MathFunctionError.nonFinite(name: name) }
        return v
    }

    /// The stable finite mean: a naive sum can overflow while the mean
    /// is finite (`average(1e308, 1e308)`). Shift by the largest value
    /// (and, if that partial sum still overflows, by the smallest) so
    /// every partial term stays bounded; the shift is exact in Double.
    static func stableAverage(_ values: [Double]) throws -> Double {
        guard !values.isEmpty else {
            throw MathFunctionError.nonFinite(name: "average")
        }
        // First try the direct (Kahan-compensated) sum: it is exact for
        // the common case and cheapest.
        var sum = 0.0
        var comp = 0.0
        var directOK = true
        for v in values {
            let y = v - comp
            let t = sum + y
            comp = (t - sum) - y
            sum = t
            if !sum.isFinite { directOK = false; break }
        }
        if directOK {
            let mean = sum / Double(values.count)
            guard mean.isFinite else { throw MathFunctionError.nonFinite(name: "average") }
            return mean
        }
        // Shifted fallback: m - v is bounded by the value spread.
        let hi = values.max()!
        var shifted = 0.0
        comp = 0.0
        var ok = true
        for v in values {
            let y = (hi - v) - comp
            let t = shifted + y
            comp = (t - shifted) - y
            shifted = t
            if !shifted.isFinite { ok = false; break }
        }
        if ok {
            let mean = hi - shifted / Double(values.count)
            guard mean.isFinite else { throw MathFunctionError.nonFinite(name: "average") }
            return mean
        }
        let lo = values.min()!
        shifted = 0
        comp = 0
        ok = true
        for v in values {
            let y = (v - lo) - comp
            let t = shifted + y
            comp = (t - shifted) - y
            shifted = t
            if !shifted.isFinite { ok = false; break }
        }
        guard ok else { throw MathFunctionError.nonFinite(name: "average") }
        let mean = lo + shifted / Double(values.count)
        guard mean.isFinite else { throw MathFunctionError.nonFinite(name: "average") }
        return mean
    }
}

// MARK: - Function-call context (shared comma/shape rules)

/// One shared pure scan that answers, for every character of a line:
/// how many function-call argument lists are open at that position, and
/// whether the line carries at least one function-shaped call head
/// (identifier + optional whitespace + `(`). The SAME scan feeds the
/// function-aware comma normalization (`normalizeExprCorrect`), the
/// thousand-grouping pass (`InputFormatting.groupDigits`) and the
/// strict "this input is function-shaped" gates, so the comma
/// ambiguity convention can never diverge between paths:
///
/// - OUTSIDE any call: every comma is a grouping comma (legacy
///   byte-for-byte: `1,234` -> `1234`).
/// - INSIDE a call: a comma is a GROUPING comma exactly when the digit
///   run after it is exactly three digits (not a longer run) and the
///   digit run before it is an integer part (not a fractional tail and
///   not an identifier tail); otherwise it is an ARGUMENT SEPARATOR.
///   Hence `sum(1,234)` = one literal 1234, `sum(1, 234)` = two args,
///   `sum(1,2,3)` = three args, and the chained grouping `1,234,567`
///   stays one literal. The space after a separator is the user's only
///   disambiguator — decimal commas remain unsupported everywhere.
public enum FunctionCalls {

    /// Per-CHARACTER call depth (0 = outside any call) plus whether the
    /// line contains at least one call head.
    public static func context(_ s: String) -> (depth: [Int], hasHead: Bool) {
        let chars = Array(s)
        let n = chars.count
        var depth = [Int](repeating: 0, count: n)
        var openCallStack = [Bool]()
        var hasHead = false
        for i in 0..<n {
            let c = chars[i]
            if c == "(" {
                openCallStack.append(isCallHead(at: i, in: chars))
                if openCallStack.last! { hasHead = true }
            } else if c == ")" {
                if !openCallStack.isEmpty { openCallStack.removeLast() }
            }
            depth[i] = openCallStack.filter { $0 }.count
        }
        return (depth, hasHead)
    }

    /// Whether the `(` at `i` opens a function-call argument list: the
    /// previous significant character (skipping spaces/tabs) ends an
    /// identifier run that contains a letter or `_` (so `a1(3)` is a
    /// call head but `2(3)` is an ordinary group). Any identifier
    /// counts — unknown names are a strict error later, and the comma
    /// convention must already preserve their argument separators.
    private static func isCallHead(at i: Int, in chars: [Character]) -> Bool {
        var k = i - 1
        while k >= 0, chars[k] == " " || chars[k] == "\t" { k -= 1 }
        guard k >= 0, isIdentChar(chars[k]) else { return false }
        var j = k
        while j - 1 >= 0, isIdentChar(chars[j - 1]) { j -= 1 }
        for t in j...k where chars[t].isLetter || chars[t] == "_" {
            return true
        }
        return false
    }

    public static func isIdentChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_"
    }

    private static func isDigit(_ c: Character) -> Bool {
        ("0"..."9").contains(c)
    }

    /// The grouping-comma decision for the comma at character index
    /// `i` (only meaningful inside a call — callers check the depth).
    public static func isGroupingComma(_ chars: [Character], at i: Int) -> Bool {
        guard i > 0, isDigit(chars[i - 1]) else { return false }
        // L: the maximal digit run ending right before the comma.
        var l = i - 1
        while l - 1 >= 0, isDigit(chars[l - 1]) { l -= 1 }
        // The run must be an INTEGER part: no decimal dot and no
        // identifier tail in front of it.
        if l > 0 {
            let b = chars[l - 1]
            if b == "." { return false }
            if isIdentChar(b) { return false }
        }
        // R: the digit run right after the comma must be EXACTLY three
        // digits (a 4+ run is a separate argument, 1-2 digits are a
        // separator).
        var r = i + 1
        var count = 0
        while r < chars.count, isDigit(chars[r]) {
            count += 1
            if count > 3 { return false }
            r += 1
        }
        return count == 3
    }

    /// Quick line-level predicate: does the line contain at least one
    /// function-shaped call head? (Strict-mode gate.)
    public static func hasCallHead(_ s: String) -> Bool {
        context(s).hasHead
    }
}
