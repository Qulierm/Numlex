import Foundation

public actor RatesService {
    public static let shared = RatesService()
    private var cached: Rates = Rates()
    private var fetchedAt: Date?
    private let ttl: TimeInterval = 3600 // 1h
    private let session: URLSession = .shared

    public func current() -> Rates { cached }

    public func load() async -> Rates {
        if let at = fetchedAt, Date().timeIntervalSince(at) < ttl {
            return cached
        }
        // Configurable endpoint via env or default
        let envURL = ProcessInfo.processInfo.environment["NUMLEX_RATES_URL"]
            ?? UserDefaults.standard.string(forKey: "NUMLEX_RATES_URL")
        let apiKey = ProcessInfo.processInfo.environment["NUMLEX_EXCHANGE_API_KEY"]
            ?? ProcessInfo.processInfo.environment["EXCHANGE_API_KEY"]
            ?? UserDefaults.standard.string(forKey: "NUMLEX_EXCHANGE_API_KEY")
        // If no endpoint/key, keep unavailable
        guard let template = envURL, !template.isEmpty, let key = apiKey, !key.isEmpty else {
            return cached
        }
        let urlStr = template.replacingOccurrences(of: "{API}", with: key)
        guard let url = URL(string: urlStr) else { return cached }
        // Try to fetch USD and EUR in parallel? For simplicity fetch once and parse
        // We support two common provider shapes: ExchangeRate-API style and generic
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 5
            let (data, _) = try await session.data(for: req)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Try to parse conversion_rates or rates
                if let rates = json["conversion_rates"] as? [String: Any] {
                    if let usd = rates["RUB"] as? Double { cached.USD = usd }
                    // EUR via cross? For ExchangeRate-API base USD, RUB is USD->RUB, EUR->RUB not directly
                }
                if let rates = json["rates"] as? [String: Any] {
                    if let v = rates["RUB"] as? Double { cached.USD = v }
                }
                // Direct fields
                if let v = json["USD"] as? Double { cached.USD = v }
                if let v = json["EUR"] as? Double { cached.EUR = v }
                if let v = json["EURUSD"] as? Double { cached.EURUSD = v }
            }
            fetchedAt = Date()
        } catch {
            // keep cached
        }
        return cached
    }

    // For testing or manual set
    public func set(_ rates: Rates) {
        cached = rates
        fetchedAt = Date()
    }
}
