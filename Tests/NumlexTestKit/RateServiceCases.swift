import Foundation
import NumlexCore

/// RateStore persistence and the single-flight RateRefresher, exercised
/// with injected local file URLs so the tests never touch the network.

private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<T, Error>?
    var done: Result<T, Error>? { lock.lock(); defer { lock.unlock() }; return result }
    func set(_ r: Result<T, Error>) { lock.lock(); result = r; lock.unlock() }
}

/// Runs an async operation to completion from a synchronous test body.
private func awaitBlocking<T: Sendable>(
    _ location: String,
    _ op: @escaping @Sendable () async throws -> T
) throws -> T {
    let box = Box<T>()
    let sem = DispatchSemaphore(value: 0)
    Task {
        do { box.set(.success(try await op())) }
        catch { box.set(.failure(error)) }
        sem.signal()
    }
    let waited = sem.wait(timeout: .now() + 30)
    guard waited == .success else {
        throw CaseFailure(message: "operation timed out", location: location)
    }
    guard let r = box.done else {
        throw CaseFailure(message: "no result", location: location)
    }
    return try r.get()
}

/// A fresh temp directory; `dir/rates.json` is the store's cache file.
private func tempStore() throws -> (dir: String, store: RateStore) {
    let dir = NSTemporaryDirectory() + "numlex-rates-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    return (dir, RateStore(directory: URL(fileURLWithPath: dir)))
}

private let samplePayload = """
{"result": "success", "time_last_update_unix": 1724563200,
 "time_next_update_unix": 1724649600,
 "time_last_update_utc": "Mon, 25 Aug 2025 00:00:00 +0000",
 "time_next_update_utc": "Tue, 26 Aug 2025 00:00:00 +0000",
 "base_code": "USD", "rates": {"USD": 1, "EUR": 0.856908, "RUB": 84.063029}}
"""

public let rateServiceCases: [EngineCase] = [
    EngineCase("store-roundtrip") {
        let (dir, store) = try tempStore()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let snap = RateSnapshot(base: "USD",
                                rates: ["USD": 1, "EUR": 0.856908],
                                fetchedAt: Date())
        try expect(store.save(snap), "save succeeds", "save")
        guard let back = store.load() else {
            throw CaseFailure(message: "saved snapshot must load back",
                              location: "RateServiceCases")
        }
        try expectEqual(back.base, "USD", "base")
        try expectClose(back.ratesTable.rate(from: "USD", to: "EUR") ?? -1,
                        0.856908, 0, "cross rate")
    },
    EngineCase("store-missing-and-corrupted") {
        let (dir, store) = try tempStore()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try expect(store.load() == nil, "missing file", "nil")
        let file = dir + "/rates.json"
        try "not json".write(toFile: file, atomically: true, encoding: .utf8)
        try expect(store.load() == nil, "corrupted file", "nil")
    },
    EngineCase("refresher-failed-fetch-keeps-empty") {
        let (dir, store) = try tempStore()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let refresher = RateRefresher(
            url: URL(fileURLWithPath: dir + "/does-not-exist.json"),
            store: store)
        let (rates, current) = try awaitBlocking("refresher-failed") {
            let r = await refresher.refresh()
            return (r, await refresher.currentRates)
        }
        try expect(rates.rate(from: "USD", to: "EUR") == nil,
                   "no table after failed fetch", "empty")
        try expect(current.rate(from: "USD", to: "EUR") == nil,
                   "state stays empty", "state")
    },
    EngineCase("refresher-fetch-installs-fiat-table") {
        let (dir, store) = try tempStore()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        // Fresh timestamp so the installed snapshot is not stale.
        let payload = samplePayload.replacingOccurrences(
            of: "1724563200", with: String(Int(Date().timeIntervalSince1970)))
        try payload.write(toFile: dir + "/payload.json", atomically: true,
                          encoding: .utf8)
        let refresher = RateRefresher(
            url: URL(fileURLWithPath: dir + "/payload.json"),
            store: store)
        let (rates, stale) = try awaitBlocking("refresher-fetch") {
            let r = await refresher.refresh()
            return (r, await refresher.isStale)
        }
        try expectEqual(rates.base, "USD", "base")
        try expectClose(rates.rate(from: "USD", to: "EUR") ?? -1, 0.856908, 0, "EUR")
        try expectClose(rates.rate(from: "EUR", to: "RUB") ?? -1,
                        84.063029 / 0.856908, 1e-9, "cross")
        try expect(stale == false, "fresh after success", "stale")
        guard let stored = store.load() else {
            throw CaseFailure(message: "success must persist the table",
                              location: "RateServiceCases")
        }
        try expectEqual(stored.base, "USD", "persisted base")
        try expectClose(stored.rates["EUR"] ?? -1, 0.856908, 0, "persisted EUR")
    },
    EngineCase("refresher-failure-falls-back-to-stale-cache") {
        let (dir, store) = try tempStore()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        // A cache that is clearly older than the TTL.
        let old = Date().addingTimeInterval(-2 * RateRefresher.refreshInterval)
        try expect(store.save(RateSnapshot(base: "USD",
                                           rates: ["USD": 1, "EUR": 0.856908],
                                           fetchedAt: old)), "seed cache", "seed")
        let refresher = RateRefresher(
            url: URL(fileURLWithPath: dir + "/missing.json"),
            store: store)
        let (rates, stale) = try awaitBlocking("refresher-fallback") {
            let r = await refresher.refresh()
            return (r, await refresher.isStale)
        }
        try expectClose(rates.rate(from: "USD", to: "EUR") ?? -1, 0.856908, 0,
                        "cache survives a failed fetch")
        try expect(stale == true, "cache marked stale", "stale")
    },
    EngineCase("refresher-set-installs-immediately") {
        let (dir, store) = try tempStore()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let refresher = RateRefresher(
            url: URL(fileURLWithPath: dir + "/missing.json"),
            store: store)
        let r = Rates(base: "USD", rates: ["USD": 1, "EUR": 2, "RUB": 3])
        let (installed, stale) = try awaitBlocking("refresher-set") {
            await refresher.set(r)
            return (await refresher.currentRates, await refresher.isStale)
        }
        try expectClose(installed.rate(from: "EUR", to: "RUB") ?? -1, 1.5, 0,
                        "O(1) cross")
        try expect(stale == false, "explicit set is fresh", "stale")
    },
]
