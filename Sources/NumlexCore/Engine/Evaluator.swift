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
        if trimmed.range(of: #"^[\s+\-*/^%().×]*$"#, options: .regularExpression) != nil { return nil }
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

/// Evaluates a whole sheet with the STRICT ONE-RESULT-PER-LOGICAL-LINE
/// contract: the returned array has exactly one indexed `SheetLine` for
/// every element of `source.components(separatedBy: "\n")`, including
/// leading, consecutive and trailing blanks and `#` comments (each
/// `.blank`), `// ` lines (`.title`) and prose (`.skip`). Variable
/// accumulation stays strictly sequential — only actual `evalLine` calls
/// touch `variables`, so non-evaluable lines never affect it, and the
/// result of every evaluable line is exactly what the per-line evaluator
/// produced. Consumers must bind output by `sourceLineIndex`, never by
/// position after any filtering.
public func evaluateSheet(_ source: String, variables: inout [String: Double], rates: Rates, decimalPlaces: Int) -> [SheetLine] {
    var rows: [SheetLine] = []
    let lines = source.components(separatedBy: "\n")
    for (index, line) in lines.enumerated() {
        let result: LineResult
        if line.trimmingCharacters(in: .whitespaces).isEmpty || line.hasPrefix("#") {
            result = .blank
        } else if line.hasPrefix("// ") {
            result = .title(String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces))
        } else if line.hasPrefix("//") {
            result = .blank
        } else if let eval = evalLine(line, variables: &variables, rates: rates, decimalPlaces: decimalPlaces) {
            result = eval
        } else {
            result = .skip
        }
        rows.append(SheetLine(sourceLineIndex: index, result: result))
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

/// Overflow-safe display formatting — a thin alias for the single shared
/// formatter (`formatDisplayValue`). The previous implementation trapped
/// on values above Int64.max via a direct `Int64(value)` cast.
public func formatNumberForDisplay(_ value: Double) -> String {
    formatDisplayValue(value)
}
