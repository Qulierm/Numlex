import Foundation
import NumlexCore

/// The Rates value type: O(1) cross rates, validation against the bundled
/// fiat catalog, provider payload decoding, and the legacy pair-key
/// persistence migration.


/// Decodes a provider payload the same way the refresher does and
/// returns the validated, base-pinned snapshot (nil on any failure).
private func providerSnapshot(_ json: String) -> RateSnapshot? {
    (try? JSONDecoder().decode(RateProviderDocument.self,
                               from: Data(json.utf8)))?.snapshot()
}

public let rateTableCases: [EngineCase] = [
    EngineCase("rates-o1-cross") {
        let r = Rates(base: "USD", rates: ["USD": 1, "EUR": 1.1, "RUB": 90])
        try expectClose(r.rate(from: "USD", to: "EUR")!, 1.1, 0, "USD->EUR")
        try expectClose(r.rate(from: "EUR", to: "USD")!, 1.0 / 1.1, 1e-12, "EUR->USD")
        try expectClose(r.rate(from: "EUR", to: "RUB")!, 90.0 / 1.1, 1e-12, "EUR->RUB")
        try expectClose(r.rate(from: "RUB", to: "EUR")!, 1.1 / 90.0, 1e-12, "RUB->EUR")
        try expectClose(r.rate(from: "USD", to: "USD")!, 1, 0, "same code")
        try expect(r.rate(from: "JPY", to: "EUR") == nil, "missing code is nil", "JPY")
        try expect(r.rate(from: "XAU", to: "EUR") == nil, "non-bundled code is nil", "XAU")
    },
    EngineCase("rates-empty-means-unavailable") {
        let r = Rates()
        try expect(r.rate(from: "USD", to: "EUR") == nil, "empty table", "unavailable")
        try expect(r.rates.isEmpty, "no entries", "entries")
    },
    EngineCase("rates-nonfinite-never-returns") {
        let inf = Rates(base: "USD", rates: ["USD": 1, "RUB": .infinity])
        try expect(inf.rate(from: "USD", to: "RUB") == nil, "inf entry", "nil")
        let nan = Rates(base: "USD", rates: ["USD": 1, "RUB": .nan])
        try expect(nan.rate(from: "USD", to: "RUB") == nil, "nan entry", "nil")
        let zero = Rates(base: "USD", rates: ["USD": 1, "RUB": 0])
        try expect(zero.rate(from: "RUB", to: "USD") == nil, "zero base entry", "nil")
    },
    EngineCase("rates-validation-drops-unbundled") {
        let raw = ["USD": 1, "EUR": 0.856908, "FAKE": 1.2, "XAU": 2000,
                   "RUB": .nan, "JPY": 0, "GBP": 0.789]
        guard let v = validatedRates(base: "USD", rates: raw) else {
            throw CaseFailure(message: "validation must keep a base",
                              location: "RateTableCases")
        }
        try expectEqual(v.base, "USD", "base")
        try expect(v.rates["USD"] == 1, "base pinned to 1", "USD")
        try expectClose(v.rates["EUR"]!, 0.856908, 0, "EUR kept")
        try expectClose(v.rates["GBP"]!, 0.789, 0, "GBP kept")
        try expect(v.rates["FAKE"] == nil, "unknown code dropped", "FAKE")
        try expect(v.rates["XAU"] == nil, "metals dropped", "XAU")
        try expect(v.rates["RUB"] == nil, "non-finite dropped", "RUB")
        try expect(v.rates["JPY"] == nil, "non-positive dropped", "JPY")
    },
    EngineCase("rates-validation-base-missing") {
        try expect(validatedRates(base: "EUR",
                                        rates: ["USD": 1, "RUB": 90]) == nil,
                   "base not in raw table", "nil")
        try expect(validatedRates(base: "USD", rates: [:]) == nil,
                   "empty table", "nil")
        try expect(validatedRates(base: "USD",
                                        rates: ["USD": .nan, "EUR": 1.1]) == nil,
                   "non-finite base", "nil")
    },
    EngineCase("rates-codable-roundtrip") {
        let r = Rates(base: "USD", rates: ["USD": 1, "EUR": 1.1, "RUB": 90])
        let data = try JSONEncoder().encode(r)
        let back = try JSONDecoder().decode(Rates.self, from: data)
        try expectEqual(back.base, "USD", "base roundtrip")
        try expectEqual(back.rates.count, 3, "entry count")
        try expectClose(back.rate(from: "EUR", to: "RUB")!, 90.0 / 1.1, 1e-12, "cross")
    },
    EngineCase("rates-legacy-pair-keys-migrate") {
        // Old persistence shape: per-pair rates keyed "<FROM><TO>".
        let legacy = Data(#"{"USD": 90, "EUR": 100, "EURUSD": 1.1}"#.utf8)
        let r = try JSONDecoder().decode(Rates.self, from: legacy)
        try expectEqual(r.base, "USD", "legacy base")
        try expectClose(r.rates["USD"] ?? 0, 1, 0, "USD pinned")
        try expectClose(r.rates["RUB"] ?? 0, 90, 0, "USD entry -> RUB")
        try expectClose(r.rates["EUR"] ?? 0, 1.1, 0, "EURUSD cross -> EUR")
    },
    EngineCase("provider-decode-live-shape") {
        let json = """
        {"result": "success", "time_last_update_unix": 1724563200,
         "time_next_update_unix": 1724649600, "time_last_update_utc": "Mon, 25 Aug 2025 00:00:00 +0000",
         "time_next_update_utc": "Tue, 26 Aug 2025 00:00:00 +0000",
         "base_code": "USD", "rates": {"USD": 1, "EUR": 0.856908, "RUB": 84.063029}}
        """
        let snap = providerSnapshot(json)
        try expect(snap != nil, "live payload must decode", "payload")
        guard let snap else {
            throw CaseFailure(message: "payload rates", location: "RateTableCases")
        }
        try expectEqual(snap.base, "USD", "base code")
        try expectClose(snap.rates["EUR"] ?? -1, 0.856908, 0, "EUR")
        try expect(snap.ratesTable.rate(from: "EUR", to: "RUB") != nil, "cross O(1)", "cross")
    },
    EngineCase("provider-decode-failure-and-bad-codes") {
        let failure = """
        {"result": "failure", "errors": ["invalid api key"], "base_code": "USD", "rates": {"USD": 1}}
        """
        try expect(providerSnapshot(failure) == nil, "result=failure", "nil")
        let noBase = """
        {"result": "success", "base_code": "XXX", "rates": {"USD": 1, "EUR": 1.1}}
        """
        try expect(providerSnapshot(noBase) == nil, "unknown base code", "nil")
        try expect(providerSnapshot("not json at all") == nil, "malformed JSON", "nil")
        let empty = """
        {"result": "success", "base_code": "USD", "rates": {}}
        """
        try expect(providerSnapshot(empty) == nil, "empty rates", "nil")
    },
    EngineCase("provider-keeps-fiat-only") {
        let json = """
        {"result": "success", "base_code": "USD",
         "rates": {"USD": 1, "BTC": 43000, "XAU": 2400, "EUR": 0.856908, "RUB": 84.063029}}
        """
        let snap = providerSnapshot(json)
        guard let rates = snap?.rates else {
            throw CaseFailure(message: "fiat filter", location: "RateTableCases")
        }
        try expect(rates["BTC"] == nil, "crypto dropped", "BTC")
        try expect(rates["XAU"] == nil, "metals dropped", "XAU")
        try expect(rates["EUR"] != nil && rates["RUB"] != nil, "fiat kept", "fiat")
    },
]
