import Testing
import NumlexTestKit

/// Real Swift Testing suite. On a full Xcode toolchain `swift test`
/// executes one test per engine case (33 cases, 40+ assertions).
@Suite("Numlex calculation engine")
struct EngineTests {
    @Test(arguments: engineCases)
    func engineCase(`case`: EngineCase) throws {
        try `case`.body()
    }

    @Test(arguments: sheetCases)
    func sheetCase(`case`: EngineCase) throws {
        try `case`.body()
    }

    @Test(arguments: syntaxCases)
    func syntaxCase(`case`: EngineCase) throws {
        try `case`.body()
    }
}
