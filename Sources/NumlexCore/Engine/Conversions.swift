import Foundation

private struct Conversion: Sendable {
    let factor: Double?
    let unit: String
    let custom: (@Sendable (Double) -> Double)?
}

private let linear: [(String, Double, String)] = [
    ("km to meter", 1000, "meters"),
    ("meter to km", 1/1000, "km"),
    ("mile to km", 1.60934, "km"),
    ("km to mile", 1/1.60934, "miles"),
    ("cm to m", 1/100, "m"),
    ("m to cm", 100, "cm"),
    ("cm to km", 1/100000, "km"),
    ("km to cm", 100000, "km"),
    ("kg to t", 1/1000, "ton"),
    ("t to kg", 1000, "kg"),
    ("mg to kg", 1/1000, "kg"),
    ("kg to mg", 1000, "mg"),
    ("ml to teaspoon", 1/5, "teaspoons"),
    ("teaspoon to ml", 5, "ml"),
    ("liter to ml", 1000, "ml"),
    ("ml to liter", 1/1000, "L"),
]

private let temps: [String: @Sendable (Double) -> Double] = [
    "f to c": { ($0 - 32) * 5/9 },
    "c to f": { $0 * 1.8 + 32 },
    "k to c": { $0 - 273.15 },
    "c to k": { $0 + 273.15 },
]
private let tempUnits: [String: String] = [
    "f to c": "C°",
    "c to f": "F°",
    "k to c": "C°",
    "c to k": "K°",
]

private let conversionMap: [String: Conversion] = {
    var m: [String: Conversion] = [:]
    for (k, f, u) in linear { m[k.lowercased()] = Conversion(factor: f, unit: u, custom: nil) }
    for (k, fn) in temps { m[k] = Conversion(factor: nil, unit: tempUnits[k] ?? "", custom: fn) }
    return m
}()

func roundResult(_ value: Double, decimalPlaces: Int) -> Double {
    if value.truncatingRemainder(dividingBy: 1) != 0 {
        let factor = pow(10.0, Double(decimalPlaces))
        // use formatted to avoid floating noise
        let s = String(format: "%.\(decimalPlaces)f", value)
        if let d = Double(s) { return d }
        return (value * factor).rounded() / factor
    }
    return value
}

func tryConversion(_ line: String, rates: Rates, decimalPlaces: Int) -> LineResult? {
    let trimmedCommas = line.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")
    guard let regex = try? NSRegularExpression(pattern: #"^([+-]?\d*\.?\d+)\s+(.+)$"#, options: .caseInsensitive) else { return nil }
    let ns = trimmedCommas as NSString
    guard let match = regex.firstMatch(in: trimmedCommas, range: NSRange(location: 0, length: ns.length)), match.numberOfRanges == 3 else { return nil }
    let numStr = ns.substring(with: match.range(at: 1))
    guard let num = Double(numStr) else { return nil }
    let restRaw = ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces).lowercased()
    let normalized = restRaw.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

    if let conv = conversionMap[normalized] {
        let result: Double = conv.custom?(num) ?? (conv.factor.map { num * $0 } ?? num)
        return .number(value: roundResult(result, decimalPlaces: decimalPlaces), unit: conv.unit)
    }
    // currency
    if let curRegex = try? NSRegularExpression(pattern: #"^(\w+)\s+to\s+(\w+)$"#, options: .caseInsensitive),
       let curMatch = curRegex.firstMatch(in: normalized, range: NSRange(location: 0, length: (normalized as NSString).length)),
       curMatch.numberOfRanges == 3 {
        let nss = normalized as NSString
        let from = nss.substring(with: curMatch.range(at: 1)).lowercased()
        let to = nss.substring(with: curMatch.range(at: 2)).lowercased()
        let key = "\(from) to \(to)"
        var value: Double? = nil
        var unit: String? = nil
        switch key {
        case "usd to rub":
            guard let r = rates.USD else { return .error(message: "Rates unavailable") }
            value = num * r; unit = "RUB"
        case "eur to rub":
            guard let r = rates.EUR else { return .error(message: "Rates unavailable") }
            value = num * r; unit = "RUB"
        case "rub to eur":
            guard let r = rates.EUR else { return .error(message: "Rates unavailable") }
            value = num / r; unit = "EUR"
        case "usd to eur":
            guard let r = rates.EURUSD else { return .error(message: "Rates unavailable") }
            value = num * r; unit = "EUR"
        case "eur to usd":
            guard let r = rates.EURUSD else { return .error(message: "Rates unavailable") }
            value = num / r; unit = "USD"
        case "rub to usd":
            guard let r = rates.USD else { return .error(message: "Rates unavailable") }
            value = num / r; unit = "usd"
        default:
            return nil
        }
        if let v = value {
            return .number(value: roundResult(v, decimalPlaces: decimalPlaces), unit: unit)
        }
    }
    return nil
}
