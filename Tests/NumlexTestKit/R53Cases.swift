import Foundation
import NumlexCore

/// r53: natural named money calculations — `apple = 5$` followed by
/// `5 people × apple` must evaluate to USD $25.00.
///
/// Root cause fixed: the typed-name stage routed money-name lines into
/// the STRICT named-expression core, which rejects bounded neutral
/// prose (`people`), so NaturalCalculation's neutral-word stripping
/// never ran; and the money core derived currency codes only from a
/// marker/ISO on the current line, not from referenced typed money
/// names. Now: the money core accepts a line whose currency comes
/// solely from a referenced typed money name (expression-shaped lines
/// only — prose stays prose), and the named stage falls back to that
/// core after the strict core rejects bounded prose.
///
/// Coverage:
/// 1. Exact user case (postfix `$` declaration) + prefix `$5`;
/// 2. Operand order, singular/plural, case/whitespace, compound name;
/// 3. Same-currency two-name arithmetic, scalar count variables,
///    natural assignment RHS (money recorded typed);
/// 4. Explicit-marker/named-money agreement and conflict; two named
///    money values with different codes; unknown prose rejection;
/// 5. Bare name and prose mention stay hidden; functions on money
///    rejected; division by people; zero/negative/decimal counts;
///    non-finite protection;
/// 6. Regressions: `$3k earnings ÷ 5 people`, named money × / +,
///    `<name> in <unit>` conversion, scalar variables.

private func r53Results(_ content: String,
                        rates: Rates = Rates()) -> [LineResult] {
    let lines = content.components(separatedBy: "\n")
    return resolveSheet(content: content,
                        lineIDs: lines.map { _ in UUID() },
                        references: [],
                        rates: rates,
                        decimalPlaces: 2,
                        constants: []).lines.map(\.result)
}

private let usd = "USD"

public let r53Cases: [EngineCase] = [
    // MARK: 1. The exact user case and declaration forms

    EngineCase("r53-exact-user-case-postfix-dollar") {
        let r = r53Results("apple = 5$\n5 people × apple")
        try expectEqual(r[0], .money(value: 5, code: usd), "postfix $ declaration")
        try expectEqual(r[1], .money(value: 25, code: usd), "people × named money")
    },

    EngineCase("r53-prefix-dollar-declaration") {
        let r = r53Results("apple = $5\n5 people × apple")
        try expectEqual(r[0], .money(value: 5, code: usd), "prefix $ declaration")
        try expectEqual(r[1], .money(value: 25, code: usd), "derived currency")
    },

    EngineCase("r53-iso-declared-name") {
        let r = r53Results("apple = 5 USD\n5 people × apple")
        try expectEqual(r[0], .money(value: 5, code: usd), "ISO declaration")
        try expectEqual(r[1], .money(value: 25, code: usd), "derived currency")
    },

    // MARK: 2. Operand order, counts, name forms

    EngineCase("r53-reversed-operands") {
        let r = r53Results("apple = 5$\napple × 5 people")
        try expectEqual(r[1], .money(value: 25, code: usd), "name × count")
    },

    EngineCase("r53-singular-person") {
        let r = r53Results("apple = 5$\n5 person × apple")
        try expectEqual(r[1], .money(value: 25, code: usd), "singular person")
    },

    EngineCase("r53-case-insensitive-flexible-whitespace") {
        let r = r53Results("Apple = 5$\n5  people × Apple")
        try expectEqual(r[0], .money(value: 5, code: usd), "capitalized declaration")
        try expectEqual(r[1], .money(value: 25, code: usd), "flexible spacing")
    },

    EngineCase("r53-compound-money-name") {
        let r = r53Results("green apple = 5$\n5 people × green apple")
        try expectEqual(r[0], .money(value: 5, code: usd), "compound declaration")
        try expectEqual(r[1], .money(value: 25, code: usd), "compound reference")
    },

    // MARK: 3. Combinations with other declared values

    EngineCase("r53-same-currency-two-names") {
        let r = r53Results("apple = 5$\npear = 2$\n5 people × apple + pear")
        try expectEqual(r[0], .money(value: 5, code: usd), "first name")
        try expectEqual(r[1], .money(value: 2, code: usd), "second name")
        try expectEqual(r[2], .money(value: 27, code: usd), "prose around two names")
    },

    EngineCase("r53-scalar-count-with-money") {
        let r = r53Results("apple = 5$\ncount = 5\ncount people × apple")
        try expectEqual(r[1], .variable(name: "count", value: 5), "scalar count")
        try expectEqual(r[2], .money(value: 25, code: usd), "count variable × money")
    },

    EngineCase("r53-natural-assignment-rhs-records-money") {
        let r = r53Results("apple = 5$\ntotal cost = 5 people × apple\ntotal cost × 2")
        try expectEqual(r[1], .money(value: 25, code: usd), "natural assignment RHS")
        try expectEqual(r[2], .money(value: 50, code: usd),
                        "assigned name is recorded typed money")
    },

    EngineCase("r53-single-identifier-assignment-named-rhs") {
        let r = r53Results("apple = 5$\nx = 5 people × apple")
        try expectEqual(r[1], .money(value: 25, code: usd), "single-identifier money RHS")
    },

    EngineCase("r53-prose-around-derived-money") {
        let r = r53Results("apple = 5$\nlunch was apple + 2 people × apple")
        try expectEqual(r[1], .money(value: 15, code: usd),
                        "neutral prose strips around derived context")
    },

    // MARK: 4. Currency agreement and conflict

    EngineCase("r53-explicit-marker-agrees-with-name") {
        let r = r53Results("apple = 5$\napple + $2")
        try expectEqual(r[1], .money(value: 7, code: usd), "marker and name agree")
    },

    EngineCase("r53-explicit-marker-conflicts-with-name") {
        let r = r53Results("apple = 5$\napple + €2")
        try expectEqual(r[1].isError, true, "marker/name currency mismatch is invalid")
    },

    EngineCase("r53-two-money-names-different-codes") {
        let r = r53Results("apple = 5$\neuro bill = 3 EUR\napple + euro bill")
        try expectEqual(r[1], .money(value: 3, code: "EUR"), "EUR declaration")
        try expectEqual(r[2].isError, true, "mixed named currencies are invalid")
    },

    // MARK: 5. Boundaries: prose, unknown words, functions, counts

    EngineCase("r53-unknown-prose-stays-invalid") {
        let r = r53Results("apple = 5$\n5 customers × apple\n5 bananas × apple")
        try expectEqual(r[1].isError, true, "customers is not a neutral word")
        try expectEqual(r[2].isError, true, "bananas is not a neutral word")
    },

    EngineCase("r53-bare-money-name-stays-hidden") {
        let r = r53Results("apple = 5$\napple")
        try expectEqual(r[1], .skip, "bare name is not a calculation")
    },

    EngineCase("r53-prose-mention-stays-prose") {
        let r = r53Results("apple = 5$\nI like apple")
        try expectEqual(r[1], .skip, "prose mentioning the name is not money")
    },

    EngineCase("r53-function-on-named-money-rejected") {
        let r = r53Results("apple = 5$\nsqrt(apple)\nsqrt(5 people × apple)")
        try expectEqual(r[1].isError, true, "function on a money name")
        try expectEqual(r[2].isError, true, "function over a named money expression")
    },

    EngineCase("r53-division-by-people") {
        let r = r53Results("apple = 5$\napple ÷ 5 people")
        try expectEqual(r[1], .money(value: 1, code: usd), "money ÷ count")
    },

    EngineCase("r53-zero-negative-decimal-counts") {
        let r = r53Results("apple = 5$\n0 people × apple\n-2 people × apple\n2.5 people × apple")
        try expectEqual(r[1], .money(value: 0, code: usd), "zero count")
        try expectEqual(r[2], .money(value: -10, code: usd), "negative count")
        try expectEqual(r[3], .money(value: 12.5, code: usd), "decimal count")
    },

    EngineCase("r53-non-finite-result-rejected") {
        let r = r53Results("apple = 5$\n5 people × apple / 0")
        try expectEqual(r[1].isError, true, "division by zero stays invalid")
    },

    // MARK: 6. No regressions

    EngineCase("r53-neutral-people-money-unchanged") {
        let r = r53Results("$3k earnings ÷ 5 people")
        try expectEqual(r[0], .money(value: 600, code: usd), "marker-driven prose money")
    },

    EngineCase("r53-named-money-times-constant-unchanged") {
        let r = r53Results("monthly rent = $1200\nmonthly rent × 12")
        try expectEqual(r[1], .money(value: 14400, code: usd), "strict named route")
    },

    EngineCase("r53-named-money-add-unchanged") {
        let r = r53Results("monthly rent = $1200\nphone bill = 45$\nmonthly rent + phone bill")
        try expectEqual(r[2], .money(value: 1245, code: usd), "two named moneys")
    },

    EngineCase("r53-named-money-conversion-unchanged") {
        let r = r53Results("monthly rent = $1200\nmonthly rent in EUR",
                           rates: Rates(base: "USD", rates: ["USD": 1, "EUR": 1.1]))
        try expectEqual(r[0], .money(value: 1200, code: usd), "declaration")
        try expectEqual(r[1], .number(value: 1320, unit: "EUR"), "conversion shape wins")
    },

    EngineCase("r53-scalar-variables-unchanged") {
        let r = r53Results("x = 5\nx × 2")
        try expectEqual(r[0], .variable(name: "x", value: 5), "scalar declaration")
        try expectEqual(r[1], .number(value: 10, unit: nil), "scalar route")
    },
]

private extension LineResult {
    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}
