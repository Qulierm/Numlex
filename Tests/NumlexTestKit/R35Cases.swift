import Foundation
import NumlexCore

/// r35: generated constant names — the deterministic, grammar-valid
/// scheme (`constant`, `constant_2`, …) replacing r33's invalid
/// `constant 2` default (digit-first word violates naturalLHS).

private func key(_ name: String) -> String { canonicalNameKey(name) }

public let r35Cases: [EngineCase] = [
    EngineCase("r35-gen-empty") {
        precondition(ConstantResolver.generatedConstantName(taken: []) == "constant")
    },

    EngineCase("r35-gen-collision-casefold") {
        precondition(ConstantResolver.generatedConstantName(taken: [key("Constant")]) == "constant_2")
        precondition(ConstantResolver.generatedConstantName(taken: [key("CONSTANT")]) == "constant_2")
        precondition(ConstantResolver.generatedConstantName(taken: [key("constant_2")]) == "constant")
    },

    EngineCase("r35-gen-suffix-run") {
        precondition(
            ConstantResolver.generatedConstantName(taken: [key("constant"), key("constant_2")])
                == "constant_3")
    },

    EngineCase("r35-gen-gap-filled") {
        precondition(
            ConstantResolver.generatedConstantName(taken: [key("constant"), key("constant_3")])
                == "constant_2")
        precondition(
            ConstantResolver.generatedConstantName(taken: [key("constant_2"), key("constant_4")])
                == "constant")
    },

    EngineCase("r35-gen-many") {
        var taken: Set<String> = [key("constant")]
        for n in 2...50 { taken.insert(key("constant_\(n)")) }
        precondition(ConstantResolver.generatedConstantName(taken: taken) == "constant_51")
    },

    EngineCase("r35-gen-grammar-valid") {
        // Black-box: every generated name must pass the resolver's
        // name grammar (no .invalidName / .reserved) and not be a
        // reserved word.
        var taken: Set<String> = []
        for _ in 0..<12 {
            let name = ConstantResolver.generatedConstantName(taken: taken)
            precondition(!ConstantResolver.isReservedName(name), name)
            let status = ConstantResolver.resolve(
                [UserConstant(name: name, expression: "0")]).rows[0].status
            if case .invalidName = status { preconditionFailure(name) }
            if case .reserved = status { preconditionFailure(name) }
            taken.insert(key(name))
        }
    },

    EngineCase("r35-gen-resolve-valid") {
        var taken: Set<String> = []
        var rows: [UserConstant] = []
        for _ in 0..<6 {
            let name = ConstantResolver.generatedConstantName(taken: taken)
            taken.insert(key(name))
            rows.append(UserConstant(name: name, expression: "0"))
        }
        let resolved = ConstantResolver.resolve(rows).rows
        for r in resolved {
            guard case .valid(let q) = r.status else {
                preconditionFailure("row \(r.name) not valid: \(r.status)")
            }
            if case .scalar(let v) = q { precondition(v == 0) } else {
                preconditionFailure("row \(r.name) non-scalar")
            }
        }
    },

    EngineCase("r35-gen-no-duplicate-with-casefold") {
        let existing = UserConstant(name: "Constant", expression: "1")
        let name = ConstantResolver.generatedConstantName(taken: [key(existing.name)])
        precondition(name == "constant_2")
        let rows = [existing, UserConstant(name: name, expression: "0")]
        let resolved = ConstantResolver.resolve(rows).rows
        if case .duplicate = resolved[0].status { preconditionFailure("existing row duplicate") }
        guard case .valid = resolved[1].status else {
            preconditionFailure("generated row not valid: \(resolved[1].status)")
        }
    }
]
