import Foundation

private func normalizeExprCorrect(_ expr: String) -> String {
    var s = expr.replacingOccurrences(of: ",", with: "")
    func expand(_ input: String, suffix: String, mult: String) -> String {
        let pattern = "(\\d+(?:\\.\\d+)?)\\s*\(suffix)\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return input }
        let ns = input as NSString
        var result = input
        let matches = regex.matches(in: input, range: NSRange(location: 0, length: ns.length)).reversed()
        for m in matches {
            let num = ns.substring(with: m.range(at: 1))
            let repl = "(\(num)*\(mult))"
            if let r = Range(m.range, in: result) { result.replaceSubrange(r, with: repl) }
        }
        return result
    }
    s = expand(s, suffix: "k", mult: "1000")
    s = expand(s, suffix: "m", mult: "1000000")
    return s
}

private func isValidIdentifier(_ name: String) -> Bool {
    guard let regex = try? NSRegularExpression(pattern: #"^[A-Za-z_]\w*$"#) else { return false }
    return regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
}

private func tryEvaluateCleaned(_ line: String, variables: [String: Double]) -> Double? {
    // Replace unknown words with empty
    var cleaned = line
    if let regex = try? NSRegularExpression(pattern: #"[A-Za-z_]\w*"#) {
        let ns = line as NSString
        let matches = regex.matches(in: line, range: NSRange(location: 0, length: ns.length)).reversed()
        for m in matches {
            let w = ns.substring(with: m.range)
            if variables[w] == nil {
                if let r = Range(m.range, in: cleaned) { cleaned.replaceSubrange(r, with: "") }
            }
        }
    }
    let trimmed = cleaned.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { return nil }
    // if only operators/parens/space and no digit -> skip
    if trimmed.range(of: #"\d"#, options: .regularExpression) == nil {
        // check if it contains only allowed chars without digit
        if trimmed.range(of: #"^[\s+\-*/^%().]*$"#, options: .regularExpression) != nil { return nil }
    }
    do {
        return try evaluateExpression(trimmed, variables: variables)
    } catch { return nil }
}

private func evalAssignment(line: String, variables: inout [String: Double], decimalPlaces: Int) -> LineResult? {
    guard let idx = line.firstIndex(of: "=") else { return nil }
    let left = String(line[..<idx]).trimmingCharacters(in: .whitespaces)
    let rightRaw = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
    let right = normalizeExprCorrect(rightRaw)
    if !isValidIdentifier(left) { return .error(message: "Invalid assignment") }
    if right.isEmpty { return .error(message: "Missing expression") }
    do {
        let raw = try evaluateExpression(right, variables: variables)
        let v = roundResult(raw, decimalPlaces: decimalPlaces)
        variables[left] = v
        return .variable(name: left, value: v)
    } catch {
        if let cleaned = tryEvaluateCleaned(right, variables: variables) {
            let v = roundResult(cleaned, decimalPlaces: decimalPlaces)
            variables[left] = v
            return .variable(name: left, value: v)
        }
        return .error(message: (error as? LocalizedError)?.errorDescription ?? "\(error)")
    }
}

private func evalFreeExpression(line: String, variables: [String: Double], decimalPlaces: Int) -> LineResult? {
    let trimmed = normalizeExprCorrect(line.trimmingCharacters(in: .whitespaces))
    if trimmed.isEmpty { return nil }
    if trimmed.range(of: #"\d"#, options: .regularExpression) == nil {
        if trimmed.range(of: #"[а-яА-ЯёЁ]"#, options: .regularExpression) != nil { return nil }
        let single = trimmed.trimmingCharacters(in: .whitespaces)
        if single.range(of: #"^[A-Za-z_]\w*$"#, options: .regularExpression) != nil, variables[single] != nil {
            // allow single known variable
        } else {
            return nil
        }
    }
    do {
        let raw = try evaluateExpression(trimmed, variables: variables)
        return .number(value: roundResult(raw, decimalPlaces: decimalPlaces), unit: nil)
    } catch {
        if let cleaned = tryEvaluateCleaned(trimmed, variables: variables) {
            return .number(value: roundResult(cleaned, decimalPlaces: decimalPlaces), unit: nil)
        }
        return .error(message: "Invalid expression")
    }
}

public func evalLine(_ line: String, variables: inout [String: Double], rates: Rates, decimalPlaces: Int) -> LineResult? {
    if let conv = tryConversion(line, rates: rates, decimalPlaces: decimalPlaces) { return conv }
    if line.contains("=") {
        return evalAssignment(line: line, variables: &variables, decimalPlaces: decimalPlaces)
    }
    return evalFreeExpression(line: line, variables: variables, decimalPlaces: decimalPlaces)
}

public func evaluateSheet(_ source: String, variables: inout [String: Double], rates: Rates, decimalPlaces: Int) -> [LineResult] {
    var rows: [LineResult] = []
    var isFirstEmpty = true
    let lines = source.components(separatedBy: "\n")
    for line in lines {
        if line.trimmingCharacters(in: .whitespaces).isEmpty || line.hasPrefix("#") {
            if !isFirstEmpty { rows.append(.blank) }
            isFirstEmpty = true
            continue
        }
        isFirstEmpty = false
        if line.hasPrefix("// ") {
            rows.append(.title(String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)))
            continue
        }
        if line.hasPrefix("//") {
            rows.append(.blank)
            isFirstEmpty = true
            continue
        }
        if let result = evalLine(line, variables: &variables, rates: rates, decimalPlaces: decimalPlaces) {
            rows.append(result)
        } else {
            rows.append(.skip)
        }
    }
    return rows
}

public func declaredVariables(_ source: String) -> [String: Bool] {
    var dict: [String: Bool] = [:]
    for line in source.components(separatedBy: "\n") {
        if let regex = try? NSRegularExpression(pattern: #"^\s*([A-Za-z_]\w*)\s*="#) {
            let ns = line as NSString
            if let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges >= 2 {
                let name = ns.substring(with: m.range(at: 1))
                dict[name] = true
            }
        }
    }
    return dict
}

public func formatNumberForDisplay(_ value: Double) -> String {
    if value.truncatingRemainder(dividingBy: 1) == 0 {
        let intVal = Int64(value)
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.groupingSeparator = ","
        fmt.locale = Locale(identifier: "en_US")
        return fmt.string(from: NSNumber(value: intVal)) ?? "\(intVal)"
    } else {
        return "\(value)"
    }
}
