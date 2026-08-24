import Foundation
import NumlexTestKit

// Standalone test runner for toolchains without the XCTest/Swift Testing
// runtime wired into SwiftPM (e.g. Command Line Tools only). Executes the
// exact same cases as the Swift Testing suite and exits non-zero on failure:
//
//     swift run NumlexTests

let allCases = engineCases + sheetCases + syntaxCases + formatCases + settingsCases + caretCases + baselineCases + spaceTypingCases + conversionCases + deletionCases + overflowCases
var failures = 0
for testCase in allCases {
    do {
        try testCase.body()
        print("✓ \(testCase.name)")
    } catch {
        failures += 1
        print("✗ \(testCase.name): \(error)")
    }
}
print("\(allCases.count - failures)/\(allCases.count) engine cases passed")
exit(failures == 0 ? 0 : 1)
