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

    @Test(arguments: formatCases)
    func formatCase(`case`: EngineCase) throws {
        try `case`.body()
    }

    @Test(arguments: settingsCases)
    func settingsCase(`case`: EngineCase) throws {
        try `case`.body()
    }

    @Test(arguments: caretCases)
    func caretCase(`case`: EngineCase) throws {
        try `case`.body()
    }

    @Test(arguments: baselineCases)
    func baselineCase(`case`: EngineCase) throws {
        try `case`.body()
    }

    @Test(arguments: spaceTypingCases)
    func spaceTypingCase(`case`: EngineCase) throws {
        try `case`.body()
    }

    @Test(arguments: conversionCases)
    func conversionCase(`case`: EngineCase) throws {
        try `case`.body()
    }

    @Test(arguments: deletionCases)
    func deletionCase(`case`: EngineCase) throws {
        try `case`.body()
    }

    @Test(arguments: overflowCases)
    func overflowCase(`case`: EngineCase) throws {
        try `case`.body()
    }

    @Test(arguments: answerReferenceCases)
    func answerReferenceCase(`case`: EngineCase) throws {
        try `case`.body()
    }

    @Test(arguments: unitCatalogCases)
    func unitCatalogCase(`case`: EngineCase) throws {
        try `case`.body()
    }

    @Test(arguments: richConversionCases)
    func richConversionCase(`case`: EngineCase) throws {
        try `case`.body()
    }

    @Test(arguments: rateTableCases)
    func rateTableCase(`case`: EngineCase) throws {
        try `case`.body()
    }

    @Test(arguments: rateServiceCases)
    func rateServiceCase(`case`: EngineCase) throws {
        try `case`.body()
    }

    @Test(arguments: moneyCases)
    func moneyCase(`case`: EngineCase) throws {
        try `case`.body()
    }

    @Test(arguments: dateCases)
    func dateCase(`case`: EngineCase) throws {
        try `case`.body()
    }

    @Test(arguments: moneyAssignmentCases)
    func moneyAssignmentCase(`case`: EngineCase) throws {
        try `case`.body()
    }

    @Test(arguments: r18Cases)
    func r18ProseMoneyAndTokenMixing(`case`: EngineCase) throws {
        try `case`.body()
    }

    @Test(arguments: r18FormatCases)
    func r18NaturalAutospacing(`case`: EngineCase) throws {
        try `case`.body()
    }

    @Test(arguments: r18AnimationCases)
    func r18TokenAppearance(`case`: EngineCase) throws {
        try `case`.body()
    }
}
