import Foundation
import NumlexCore

private func minimalModeReadSource(_ relativePath: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // NumlexTestKit
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repository root
    let url = root.appendingPathComponent(relativePath)
    guard let source = try? String(contentsOf: url, encoding: .utf8) else {
        throw CaseFailure(message: "missing source file \(relativePath)", location: "MinimalModeCases")
    }
    return source
}

private func minimalModeAppSourceCount(_ marker: String) throws -> Int {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // NumlexTestKit
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repository root
    let sourceRoot = root.appendingPathComponent("Sources/NumlexApp", isDirectory: true)
    guard let enumerator = FileManager.default.enumerator(
        at: sourceRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
        throw CaseFailure(message: "cannot enumerate NumlexApp sources", location: "MinimalModeCases")
    }
    var count = 0
    while let url = enumerator.nextObject() as? URL {
        guard url.pathExtension == "swift" else { continue }
        let source = try String(contentsOf: url, encoding: .utf8)
        count += source.components(separatedBy: marker).count - 1
    }
    return count
}

/// Pure Minimal Mode policy and geometry cases. The native coordinator supplies
/// live frame/contentLayoutRect measurements and connected screen rectangles.
public let minimalModeCases: [EngineCase] = [
    EngineCase("minimal-mode-content-target-uses-existing-main-minima") {
        try expectEqual(MinimalModeGeometry.compactContentSize,
                        CGSize(width: 600, height: 260),
                        "Minimal Mode content target")
        try expectEqual(MinimalModeGeometry.compactContentSize.width,
                        MainWindowGeometry.contentMinWidth,
                        "reuse existing content width minimum")
        try expectEqual(MinimalModeGeometry.compactContentSize.height,
                        MainWindowGeometry.minContentHeight,
                        "reuse existing content height minimum")
        try expectEqual(MainWindowGeometry.expandedMinFrameWidth, 800,
                        "normal expanded frame floor is unchanged")
        try expectEqual(MainWindowGeometry.collapsedMinFrameWidth, 600,
                        "normal collapsed frame floor is unchanged")
    },

    EngineCase("minimal-mode-visibility-is-a-nonmutating-normal-preference-projection") {
        for sidebar in [false, true] {
            for total in [false, true] {
                try expectEqual(
                    MinimalModePresentation.sidebarVisible(isMinimalMode: false,
                                                            normalSidebarVisible: sidebar),
                    sidebar, "normal sidebar preference remains authoritative")
                try expectEqual(
                    MinimalModePresentation.showTotalBar(isMinimalMode: false,
                                                          normalShowTotalBar: total),
                    total, "normal Floating Total preference remains authoritative")
                try expect(!MinimalModePresentation.sidebarVisible(isMinimalMode: true,
                                                                   normalSidebarVisible: sidebar),
                           "Minimal Mode hides the sidebar for either saved value")
                try expect(!MinimalModePresentation.showTotalBar(isMinimalMode: true,
                                                                 normalShowTotalBar: total),
                           "Minimal Mode hides the Floating Total for either saved value")
            }
        }
    },

    EngineCase("minimal-mode-normal-frame-persistence-is-suppressed-while-owned") {
        let scenarios: [(String, Bool, Bool, Bool, Bool)] = [
            ("settled normal", false, false, false, true),
            ("settled compact", true, false, false, false),
            ("entry transition", true, true, false, false),
            ("exit transition", false, true, false, false),
            ("native full-screen", false, false, true, false),
            ("termination while compact", true, false, false, false),
            ("termination during transition", false, true, false, false),
            ("termination after normal restoration", false, false, false, true)
        ]
        for (name, minimal, transitioning, fullScreen, expected) in scenarios {
            try expectEqual(
                MinimalModePresentation.shouldPersistNormalFrame(
                    isMinimalMode: minimal,
                    isTransitioning: transitioning,
                    isNativeFullScreen: fullScreen),
                expected, "normal-frame eligibility: \(name)")
        }
    },

    EngineCase("minimal-mode-enter-uses-native-frame-size-and-preserves-top-right") {
        let normal = CGRect(x: 200, y: 120, width: 920, height: 700)
        let nativeCompactFrame = CGSize(width: 610, height: 314)
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let compact = MinimalModeGeometry.enteringFrame(
            from: normal,
            compactFrameSize: nativeCompactFrame,
            visibleFrames: [screen])
        try expectEqual(compact,
                        CGRect(x: 510, y: 506, width: 610, height: 314),
                        "use the AppKit-converted frame size and keep its top-right")
        if let compact {
            try expectEqual(compact.maxX, normal.maxX, "right edge stays anchored")
            try expectEqual(compact.maxY, normal.maxY, "top edge stays anchored")
        }
    },

    EngineCase("minimal-mode-enter-retains-actual-native-chrome-contribution") {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let normal = CGRect(x: 100, y: 100, width: 900, height: 700)
        for chromeHeight in [0.0, 26.0, 52.0, 54.0] as [CGFloat] {
            let liveFrameSize = CGSize(width: 900, height: 700)
            let liveContentLayoutSize = CGSize(width: 900, height: 700 - chromeHeight)
            guard let measuredFrameSize = MinimalModeGeometry.compactFrameSize(
                currentFrameSize: liveFrameSize,
                currentContentLayoutSize: liveContentLayoutSize) else {
                throw CaseFailure(message: "live chrome conversion rejected valid sizes", location: "MinimalModeCases")
            }
            try expectEqual(measuredFrameSize,
                            CGSize(width: 600, height: 260 + chromeHeight),
                            "derive the compact frame from live chrome for \(chromeHeight) pt")
            let compact = MinimalModeGeometry.enteringFrame(
                from: normal, compactFrameSize: measuredFrameSize,
                visibleFrames: [screen])
            try expectEqual(compact?.size, measuredFrameSize,
                            "the clamp uses the measured frame target")
            try expectEqual(compact?.maxY, normal.maxY,
                            "measured chrome preserves the top edge")
        }
        let fullSizeHostingSamples: [(CGFloat, CGFloat, CGFloat)] = [
            (600, 548, 312), (600, 574, 286), (600, 600, 260)
        ]
        for (frameHeight, layoutHeight, targetHeight) in fullSizeHostingSamples {
            guard let measured = MinimalModeGeometry.compactFrameSize(
                currentFrameSize: CGSize(width: 600, height: frameHeight),
                currentContentLayoutSize: CGSize(width: 600, height: layoutHeight)) else {
                throw CaseFailure(message: "full-size hosting measurement rejected", location: "MinimalModeCases")
            }
            try expectEqual(measured, CGSize(width: 600, height: targetHeight),
                            "usable 600 x 260 content plus measured native chrome")
        }
    },

    EngineCase("minimal-mode-enter-selects-largest-overlap-and-primary-tie") {
        let left = CGRect(x: -1000, y: 0, width: 1000, height: 800)
        let right = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let compactSize = CGSize(width: 600, height: 314)

        let mostlyRight = MinimalModeGeometry.enteringFrame(
            from: CGRect(x: -100, y: 100, width: 900, height: 400),
            compactFrameSize: compactSize,
            visibleFrames: [left, right],
            primaryVisibleFrame: left)
        try expect((mostlyRight?.minX ?? -1) >= 0,
                   "largest intersection wins over primary fallback")

        let tied = MinimalModeGeometry.enteringFrame(
            from: CGRect(x: -100, y: 100, width: 200, height: 200),
            compactFrameSize: compactSize,
            visibleFrames: [left, right],
            primaryVisibleFrame: right)
        try expect((tied?.minX ?? -1) >= 0,
                   "the primary screen deterministically wins an exact overlap tie")

        let disconnected = MinimalModeGeometry.enteringFrame(
            from: CGRect(x: 5000, y: 5000, width: 900, height: 700),
            compactFrameSize: compactSize,
            visibleFrames: [left, right],
            primaryVisibleFrame: left)
        try expectEqual(disconnected,
                        CGRect(x: -600, y: 486, width: 600, height: 314),
                        "no intersection falls back to the connected primary screen")
    },

    EngineCase("minimal-mode-negative-origin-and-smaller-than-floor-screen") {
        let negativeScreen = CGRect(x: -1512, y: -200, width: 1512, height: 944)
        let fromNegativeDisplay = MinimalModeGeometry.enteringFrame(
            from: CGRect(x: -1200, y: -100, width: 900, height: 700),
            compactFrameSize: CGSize(width: 600, height: 314),
            visibleFrames: [negativeScreen])
        try expect(fromNegativeDisplay != nil,
                   "negative display coordinates are valid")
        if let frame = fromNegativeDisplay {
            try expect(frame.minX >= negativeScreen.minX && frame.maxX <= negativeScreen.maxX,
                       "compact frame remains horizontally reachable on the negative display")
            try expect(frame.minY >= negativeScreen.minY && frame.maxY <= negativeScreen.maxY,
                       "compact frame remains vertically reachable on the negative display")
        }

        let tinyScreen = CGRect(x: -900, y: 10, width: 500, height: 200)
        let pinned = MinimalModeGeometry.enteringFrame(
            from: CGRect(x: 200, y: 100, width: 900, height: 700),
            compactFrameSize: CGSize(width: 600, height: 314),
            visibleFrames: [tinyScreen])
        try expectEqual(pinned,
                        CGRect(x: -900, y: -104, width: 600, height: 314),
                        "retain the compact minimum and pin the top-left on a tiny screen")
        if let pinned {
            try expect(pinned.width.isFinite && pinned.height.isFinite
                       && pinned.width > 0 && pinned.height > 0,
                       "screen clamps never produce invalid sizes")
        }
    },

    EngineCase("minimal-mode-invalid-frames-sizes-and-screens-are-rejected") {
        let goodScreen = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let goodNormal = CGRect(x: 100, y: 100, width: 900, height: 700)
        for bad in [CGRect.zero,
                    CGRect(x: 0, y: 0, width: 0, height: 10),
                    CGRect(x: CGFloat.nan, y: 0, width: 10, height: 10),
                    CGRect(x: CGFloat.greatestFiniteMagnitude, y: 0,
                           width: CGFloat.greatestFiniteMagnitude, height: 10)] {
            try expect(!MinimalModeGeometry.isValidFrame(bad),
                       "invalid frame is rejected: \(bad)")
            try expect(MinimalModeGeometry.enteringFrame(
                from: bad, compactFrameSize: CGSize(width: 600, height: 314),
                visibleFrames: [goodScreen]) == nil,
                       "invalid normal frame is never applied")
        }
        for badSize in [CGSize.zero,
                        CGSize(width: CGFloat.infinity, height: 314),
                        CGSize(width: 600, height: CGFloat.nan),
                        CGSize(width: -1, height: 314)] {
            try expect(MinimalModeGeometry.enteringFrame(
                from: goodNormal, compactFrameSize: badSize,
                visibleFrames: [goodScreen]) == nil,
                       "invalid native compact size is rejected")
        }
        let invalidMeasurements: [(CGSize, CGSize, String)] = [
            (.zero, CGSize(width: 600, height: 548), "zero native frame"),
            (CGSize(width: 600, height: 600), .zero, "zero contentLayoutRect"),
            (CGSize(width: CGFloat.infinity, height: 600), CGSize(width: 600, height: 548),
             "infinite native frame"),
            (CGSize(width: 600, height: 600), CGSize(width: 600, height: CGFloat.nan),
             "NaN contentLayoutRect"),
            (CGSize(width: -1, height: 600), CGSize(width: 600, height: 548),
             "negative native frame"),
            (CGSize(width: 600, height: 600), CGSize(width: 600, height: -1),
             "negative contentLayoutRect")
        ]
        for (frameSize, layoutSize, label) in invalidMeasurements {
            try expect(MinimalModeGeometry.compactFrameSize(
                currentFrameSize: frameSize,
                currentContentLayoutSize: layoutSize) == nil,
                       "invalid live geometry is rejected: \(label)")
        }
        let noPositiveChrome = MinimalModeGeometry.compactFrameSize(
            currentFrameSize: CGSize(width: 600, height: 600),
            currentContentLayoutSize: CGSize(width: 620, height: 620))
        try expectEqual(noPositiveChrome, CGSize(width: 600, height: 260),
                        "negative frame/layout deltas contribute no assumed chrome")
        try expect(MinimalModeGeometry.enteringFrame(
            from: goodNormal, compactFrameSize: CGSize(width: 600, height: 314),
            visibleFrames: [CGRect.zero]) == nil,
                   "no valid connected display means no frame request")
        try expect(MinimalModeGeometry.restoringFrame(
            cachedNormalFrame: nil, savedNormalFrame: nil,
            visibleFrames: [goodScreen], minimumSize: CGSize(width: 800, height: 300)) == nil,
                   "there is no restore frame without a snapshot or saved frame")

        let negativeSaved = SavedWindowFrame(x: 0, y: 0, width: -1, height: 10)
        try expect(!negativeSaved.hasUsableSize,
                   "the untrusted saved-frame value rejects negative dimensions")
        try expect(MinimalModeGeometry.restoringFrame(
            cachedNormalFrame: nil, savedNormalFrame: negativeSaved,
            visibleFrames: [goodScreen], minimumSize: CGSize(width: 800, height: 300)) == nil,
                   "negative saved dimensions never enter a CGRect restore")
    },

    EngineCase("minimal-mode-exit-returns-exact-valid-cached-normal-frame") {
        let left = CGRect(x: -1512, y: 0, width: 1512, height: 944)
        let cached = CGRect(x: -1100, y: 70, width: 900, height: 600)
        let restored = MinimalModeGeometry.restoringFrame(
            cachedNormalFrame: cached,
            savedNormalFrame: SavedWindowFrame(x: 100, y: 100, width: 800, height: 500),
            visibleFrames: [left],
            minimumSize: CGSize(width: 800, height: 300))
        try expectEqual(restored, cached,
                        "a valid cached normal frame wins and restores exactly")
    },

    EngineCase("minimal-mode-exit-clamps-disconnected-frame-and-requested-floor") {
        let currentDisplay = CGRect(x: 0, y: 0, width: 1000, height: 700)
        let oldFrame = CGRect(x: -1700, y: 150, width: 700, height: 500)
        let restored = MinimalModeGeometry.restoringFrame(
            cachedNormalFrame: oldFrame,
            savedNormalFrame: nil,
            visibleFrames: [currentDisplay],
            primaryVisibleFrame: currentDisplay,
            minimumSize: CGSize(width: MainWindowGeometry.expandedMinFrameWidth, height: 400))
        try expectEqual(restored, CGRect(x: 0, y: 150, width: 800, height: 500),
                        "display changes clamp while honoring the requested normal floor")

        let tinyDisplay = CGRect(x: -300, y: -50, width: 500, height: 300)
        let pinned = MinimalModeGeometry.restoringFrame(
            cachedNormalFrame: CGRect(x: 5000, y: 5000, width: 900, height: 600),
            savedNormalFrame: nil,
            visibleFrames: [tinyDisplay],
            primaryVisibleFrame: tinyDisplay,
            minimumSize: CGSize(width: 800, height: 400))
        try expectEqual(pinned, CGRect(x: -300, y: -150, width: 800, height: 400),
                        "keep the requested minimum and pin top-left on a smaller display")
    },

    EngineCase("minimal-mode-enter-exit-roundtrip-has-no-cumulative-drift") {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let normal = CGRect(x: 140, y: 100, width: 900, height: 700)
        let nativeCompactFrame = CGSize(width: 600, height: 314)
        for _ in 0..<20 {
            let compact = MinimalModeGeometry.enteringFrame(
                from: normal, compactFrameSize: nativeCompactFrame,
                visibleFrames: [screen])
            try expectEqual(compact, CGRect(x: 440, y: 486, width: 600, height: 314),
                            "enter geometry remains stable")
            let restored = MinimalModeGeometry.restoringFrame(
                cachedNormalFrame: normal, savedNormalFrame: nil,
                visibleFrames: [screen], minimumSize: CGSize(width: 800, height: 300))
            try expectEqual(restored, normal, "exit returns the original cached geometry")
        }
    },

    EngineCase("minimal-mode-total-preference-changes-remain-hidden-and-are-restored") {
        var normalShowTotal = true
        for changedPreference in [false, true, false] {
            normalShowTotal = changedPreference
            try expect(!MinimalModePresentation.showTotalBar(
                isMinimalMode: true, normalShowTotalBar: normalShowTotal),
                       "the current preference cannot reveal the footer while mode is active")
            try expectEqual(MinimalModePresentation.showTotalBar(
                isMinimalMode: false, normalShowTotalBar: normalShowTotal),
                changedPreference, "exit uses the latest normal preference")
        }
    },

    EngineCase("minimal-mode-both-footer-placements-hide-but-inline-total-still-evaluates") {
        let source = "5\n3\ntotal"
        var baselineVariables: [String: Double] = [:]
        let baselineRows = evaluateSheet(source, variables: &baselineVariables,
                                         rates: Rates(), decimalPlaces: 7)
        try expectEqual(baselineRows.count, 3, "inline total keeps its logical row")
        try expect(baselineRows.last?.isTotal == true,
                   "the inline total is still evaluated as a derived total row")

        for avoidsOverlap in [true, false] {
            let normalPlacement = FooterTotalPlacement.resolve(
                show: true, hasSummary: true, avoidOverlap: avoidsOverlap)
            try expectEqual(normalPlacement,
                            avoidsOverlap ? .reserved : .overlay,
                            "normal mode retains its selected footer placement")
            let effectiveShow = MinimalModePresentation.showTotalBar(
                isMinimalMode: true, normalShowTotalBar: true)
            let compactPlacement = FooterTotalPlacement.resolve(
                show: effectiveShow, hasSummary: true, avoidOverlap: avoidsOverlap)
            try expectEqual(compactPlacement, .hidden,
                            "Minimal Mode removes both overlay and reserved placement")

            var modeVariables: [String: Double] = [:]
            let modeRows = evaluateSheet(source, variables: &modeVariables,
                                         rates: Rates(), decimalPlaces: 7)
            try expectEqual(modeRows, baselineRows,
                            "footer visibility does not mutate/effect inline evaluation")
        }
    },

    EngineCase("minimal-mode-two-window-state-projections-are-independent") {
        var firstWindowMode = false
        var secondWindowMode = false
        let firstSidebarPreference = true
        let firstTotalPreference = true
        let secondSidebarPreference = true
        let secondTotalPreference = false

        firstWindowMode = true
        try expect(!MinimalModePresentation.sidebarVisible(
            isMinimalMode: firstWindowMode,
            normalSidebarVisible: firstSidebarPreference),
                   "the first window hides its sidebar")
        try expect(!MinimalModePresentation.showTotalBar(
            isMinimalMode: firstWindowMode,
            normalShowTotalBar: firstTotalPreference),
                   "the first window hides its footer")
        try expect(MinimalModePresentation.sidebarVisible(
            isMinimalMode: secondWindowMode,
            normalSidebarVisible: secondSidebarPreference),
                   "the second window keeps its own visible sidebar")
        try expect(!MinimalModePresentation.showTotalBar(
            isMinimalMode: secondWindowMode,
            normalShowTotalBar: secondTotalPreference),
                   "the second window independently honors its hidden footer preference")

        secondWindowMode = true
        firstWindowMode = false
        try expect(MinimalModePresentation.sidebarVisible(
            isMinimalMode: firstWindowMode,
            normalSidebarVisible: firstSidebarPreference),
                   "exiting in one window restores its own normal sidebar")
        try expect(MinimalModePresentation.showTotalBar(
            isMinimalMode: firstWindowMode,
            normalShowTotalBar: firstTotalPreference),
                   "exiting in one window restores its own total preference")
        try expect(!MinimalModePresentation.sidebarVisible(
            isMinimalMode: secondWindowMode,
            normalSidebarVisible: secondSidebarPreference),
                   "the other window remains independently minimal")
    },

    EngineCase("minimal-mode-only-latest-owned-geometry-request-is-current") {
        var latest: UInt64 = 0
        latest &+= 1
        let firstRequest = latest
        latest &+= 1
        let secondRequest = latest
        try expect(!MinimalModePresentation.isCurrentGeometryRequest(
            requestGeneration: firstRequest, latestGeneration: latest, ownsWindow: true),
                   "a stale request cannot overwrite a newer transition")
        try expect(MinimalModePresentation.isCurrentGeometryRequest(
            requestGeneration: secondRequest, latestGeneration: latest, ownsWindow: true),
                   "the newest request is current for its owner")
        latest &+= 1
        let thirdRequest = latest
        try expect(!MinimalModePresentation.isCurrentGeometryRequest(
            requestGeneration: secondRequest, latestGeneration: latest, ownsWindow: true),
                   "a rapid subsequent toggle invalidates the prior animation completion")
        try expect(!MinimalModePresentation.isCurrentGeometryRequest(
            requestGeneration: thirdRequest, latestGeneration: latest, ownsWindow: false),
                   "a latest request still cannot act after its window is detached")
        try expect(MinimalModePresentation.isCurrentGeometryRequest(
            requestGeneration: thirdRequest, latestGeneration: latest, ownsWindow: true),
                   "only the latest request on the still-owned window may apply")
    },

    EngineCase("minimal-mode-compact-user-resize-still-restores-cached-normal-frame") {
        let cachedNormal = CGRect(x: -1100, y: 100, width: 960, height: 700)
        let userResizedCompact = CGRect(x: -1450, y: 0, width: 700, height: 420)
        try expect(userResizedCompact.size != cachedNormal.size,
                   "the compact window can have a distinct user-sized rectangle")
        let screen = CGRect(x: -1512, y: 0, width: 1512, height: 944)
        let restored = MinimalModeGeometry.restoringFrame(
            cachedNormalFrame: cachedNormal,
            savedNormalFrame: SavedWindowFrame(x: 100, y: 100, width: 800, height: 500),
            visibleFrames: [screen],
            minimumSize: CGSize(width: MainWindowGeometry.collapsedMinFrameWidth, height: 300))
        try expectEqual(restored, cachedNormal,
                        "compact resizing never replaces the pre-entry normal snapshot")
    },

    EngineCase("minimal-mode-exit-uses-current-normal-sidebar-dependent-floor") {
        let display = CGRect(x: 0, y: 0, width: 1200, height: 900)
        let cached = CGRect(x: 100, y: 100, width: 650, height: 400)
        let collapsed = MinimalModeGeometry.restoringFrame(
            cachedNormalFrame: cached, savedNormalFrame: nil,
            visibleFrames: [display], primaryVisibleFrame: display,
            minimumSize: CGSize(width: MainWindowGeometry.collapsedMinFrameWidth, height: 300))
        try expectEqual(collapsed, cached,
                        "a hidden-sidebar request keeps the valid cached frame unchanged")
        let expanded = MinimalModeGeometry.restoringFrame(
            cachedNormalFrame: cached, savedNormalFrame: nil,
            visibleFrames: [display], primaryVisibleFrame: display,
            minimumSize: CGSize(width: MainWindowGeometry.expandedMinFrameWidth, height: 300))
        try expectEqual(expanded, CGRect(x: 0, y: 100, width: 800, height: 400),
                        "a visible-sidebar request expands to its current normal floor")
    },

    EngineCase("minimal-mode-source-view-menu-localization-and-no-persisted-mode-key") {
        let view = try minimalModeReadSource("Sources/NumlexApp/Views/ContentView.swift")
        let commands = try minimalModeReadSource("Sources/NumlexApp/MinimalModeCommands.swift")
        let settings = try minimalModeReadSource("Sources/NumlexCore/Models/Settings.swift")
        let localization = try minimalModeReadSource("Sources/NumlexCore/Localization.swift")
        let app = try minimalModeReadSource("Sources/NumlexApp/NumlexApp.swift")
        let appModel = try minimalModeReadSource("Sources/NumlexApp/AppModel.swift")
        let settingsView = try minimalModeReadSource("Sources/NumlexApp/Views/SettingsView.swift")
        let welcomeView = try minimalModeReadSource("Sources/NumlexApp/Views/WelcomeView.swift")
        let persistence = try minimalModeReadSource("Sources/NumlexCore/Services/Persistence.swift")
        let export = try minimalModeReadSource("Sources/NumlexCore/Export/ExportSnapshotBuilder.swift")
        let standaloneRunner = try minimalModeReadSource("Tests/NumlexTests/main.swift")
        let swiftTestingRunner = try minimalModeReadSource("Tests/NumlexCoreTests/EngineTests.swift")
        try expect(view.contains("@State private var isMinimalMode = false"),
                   "the mode is an initially-off ContentView/window state")
        try expect(view.components(separatedBy: "ToolbarItem(placement: .primaryAction)").count - 1 == 0,
                   "the titlebar no longer has a Minimal Mode toolbar action")
        try expect(view.components(separatedBy: "ToolbarItem(placement: .primaryAction)").count - 1 == 0
                   && commands.components(separatedBy: "Toggle(").count - 1 == 1,
                   "the one checked menu toggle replaces the titlebar control")
        try expect(view.contains(".focusedSceneValue(\\.minimalModeCommandContext, minimalModeCommandContext)"),
                   "only this main ContentView scene publishes the command context")
        try expect(commands.contains("CommandGroup(after: .sidebar)"),
                   "the command is inserted into the existing View menu")
        try expect(commands.contains(#"Toggle(L10n.t("minimalMode.menu""#),
                   "the item is a localized checked Toggle")
        try expect(commands.contains(#".keyboardShortcut("m", modifiers: [.command, .shift])"#),
                   "the menu item owns Command-Shift-M")
        try expect(commands.contains(#"@FocusedValue(\.minimalModeCommandContext)"#),
                   "the command reads its focused scene context")
        try expect(commands.contains("isOn: context?.isOn ?? .constant(false)")
                   && commands.contains(".disabled(context?.isEnabled != true)"),
                   "missing or unavailable contexts render disabled/off")


        try expectEqual(app.components(separatedBy: "MinimalModeCommands(language:").count - 1,
                        1, "the focused command collection is registered once")
        guard let settingsSceneStart = app.range(of: "        Settings {") else {
            throw CaseFailure(message: "Settings scene registration is missing", location: "MinimalModeCases")
        }
        let settingsScene = String(app[settingsSceneStart.lowerBound...])
        try expect(!settingsScene.contains("MinimalModeCommands")
                   && !settingsScene.contains("focusedSceneValue(\\.minimalModeCommandContext"),
                   "the Settings scene publishes no Minimal Mode command target")
        try expect(!settingsView.contains("minimalModeCommandContext")
                   && !welcomeView.contains("minimalModeCommandContext"),
                   "Settings and welcome views have no focused command publisher")
        try expect(view.contains("guard owningWindowReady && minimalModeCommandAvailable")
                   && view.contains("requested != isMinimalMode"),
                   "the live per-window binding rechecks key-window eligibility and ignores no-ops")
        try expect(!settings.contains("minimalMode"),
                   "AppSettings has no persisted mode key")
        try expect(!view.contains("setFrameAutosaveName"),
                   "no competing frame-autosave source is added")
        try expectEqual(commands.components(separatedBy: "CommandGroup(after: .sidebar)").count - 1,
                        1, "exactly one Minimal Mode View command group")
        try expectEqual(commands.components(separatedBy: "Toggle(").count - 1,
                        1, "the View group owns exactly one checked mode item")
        try expectEqual(try minimalModeAppSourceCount(#".keyboardShortcut("m", modifiers: [.command, .shift])"#),
                        1, "Command-Shift-M is unique across the app")
        try expectEqual(try minimalModeAppSourceCount(#".focusedSceneValue(\.minimalModeCommandContext, minimalModeCommandContext)"#),
                        1, "the focused Minimal Mode scene target has one publisher")
        try expect(standaloneRunner.contains("+ minimalModeCases"),
                   "the standalone runner includes the shared Minimal Mode cases")
        try expect(swiftTestingRunner.contains("@Test(arguments: minimalModeCases)"),
                   "the Swift Testing runner includes the same cases")
        let expectedMenuLabels: [String: String] = [
            "en": "Minimal Mode",
            "ru": "Минималистичный режим",
            "de": "Minimalmodus",
            "fr": "Mode minimaliste",
            "it": "Modalità minimalista",
            "zh": "极简模式"
        ]
        try expectEqual(localization.components(separatedBy: "\"minimalMode.menu\":").count - 1,
                        AppLanguage.allCases.count,
                        "the localized View label exists in every language dictionary")
        for language in AppLanguage.allCases {
            guard let expected = expectedMenuLabels[language.rawValue] else {
                throw CaseFailure(message: "missing expected View label for \(language.rawValue)",
                                  location: "MinimalModeCases")
            }
            try expectEqual(L10n.t("minimalMode.menu", language: language), expected,
                            "the View menu label is exact in \(language.rawValue)")
        }
        try expect(!settings.contains("minimalMode")
                   && !appModel.contains("minimalMode")
                   && !persistence.contains("minimalMode")
                   && !export.contains("minimalMode")
                   && persistence.contains("public static let currentVersion = 2"),
                   "mode routing adds no AppModel/StorePayload/export schema state")
    },

    EngineCase("minimal-mode-focused-command-is-gated-by-current-owned-main-window") {
        let view = try minimalModeReadSource("Sources/NumlexApp/Views/ContentView.swift")
        let commands = try minimalModeReadSource("Sources/NumlexApp/MinimalModeCommands.swift")
        let app = try minimalModeReadSource("Sources/NumlexApp/NumlexApp.swift")
        try expect(app.contains("private var sidebarToggleHiddenForWelcome: Bool")
                   && app.contains("revealStage != .app")
                   && view.contains("forceHideSidebarButton: sidebarToggleHiddenForWelcome"),
                   "welcome and reveal stages feed the coordinator's command-disable gate")
        try expect(view.contains("@State private var owningWindowReady = false")
                   && view.contains("@State private var minimalModeCommandAvailable = false"),
                   "missing/unready contexts begin unavailable")
        guard let contextStart = view.range(of: "private var minimalModeCommandContext: MinimalModeCommandContext?"),
              let contextEnd = view.range(of: "/// The native sidebar command talks",
                                          range: contextStart.upperBound..<view.endIndex) else {
            throw CaseFailure(message: "focused command context is missing", location: "MinimalModeCases")
        }
        let context = String(view[contextStart.lowerBound..<contextEnd.lowerBound])
        try expect(context.contains("guard enabled else { return nil }")
                   && context.contains("let enabled = owningWindowReady && minimalModeCommandAvailable"),
                   "unready/fullscreen/welcome owners publish no active binding")
        try expect(context.contains("isOn: Binding(")
                   && context.contains("get: { isMinimalMode }")
                   && context.contains("set: { requested in")
                   && context.contains("requested != isMinimalMode"),
                   "the checked View Toggle stays live against this window's session state")
        guard let eligibilityStart = view.range(of: "private func modeCommandIsEligible(for window: NSWindow)"),
              let eligibilityEnd = view.range(of: "private func publishMinimalModeCommandAvailability()",
                                              range: eligibilityStart.upperBound..<view.endIndex) else {
            throw CaseFailure(message: "owned key-window eligibility helper is missing", location: "MinimalModeCases")
        }
        let eligibility = String(view[eligibilityStart.lowerBound..<eligibilityEnd.lowerBound])
        for condition in ["owns(window)", "isWindowReady", "window.isKeyWindow", "!forcedHide",
                          "!nativeFullScreen", "!nativeFullScreenTransition", "!modeTransitionInFlight"] {
            try expect(eligibility.contains(condition), "command eligibility requires \(condition)")
        }
        guard let updateStart = view.range(of: "func updateInputs(view: WindowAttachmentView,"),
              let updateEnd = view.range(of: "/// Own only the NSWindow reached",
                                         range: updateStart.upperBound..<view.endIndex) else {
            throw CaseFailure(message: "coordinator input refresh is missing", location: "MinimalModeCases")
        }
        let update = String(view[updateStart.lowerBound..<updateEnd.lowerBound])
        try expect(update.contains("let welcomeAvailabilityChanged = self.forcedHide != forcedHide")
                   && update.contains("self.forcedHide = forcedHide")
                   && update.contains("if welcomeAvailabilityChanged { publishMinimalModeCommandAvailability() }"),
                   "welcome/reveal input changes publish fresh disabled/enabled state")
        guard let observerStart = view.range(of: "private func installOwnedWindowObservers("),
              let observerEnd = view.range(of: "private func scheduleToolbarReassertions(",
                                           range: observerStart.upperBound..<view.endIndex) else {
            throw CaseFailure(message: "owned key observers are missing", location: "MinimalModeCases")
        }
        let observers = String(view[observerStart.lowerBound..<observerEnd.lowerBound])
        try expect(observers.contains("forName: NSWindow.didBecomeKeyNotification, object: window")
                   && observers.contains("forName: NSWindow.didResignKeyNotification, object: window")
                   && observers.contains("self.owns(window)"),
                   "both owned key-window observers reject foreign owners")
        guard let becomeStart = observers.range(of: "forName: NSWindow.didBecomeKeyNotification"),
              let resignStart = observers.range(of: "keyResignObserver ="),
              let itemStart = observers.range(of: "itemObserver =") else {
            throw CaseFailure(message: "key and resign observer boundaries are missing", location: "MinimalModeCases")
        }
        let becomeObserver = String(observers[becomeStart.lowerBound..<resignStart.lowerBound])
        let resignObserver = String(observers[resignStart.lowerBound..<itemStart.lowerBound])
        try expect(becomeObserver.contains("object: window") && becomeObserver.contains("self.owns(window)")
                   && becomeObserver.contains("publishMinimalModeCommandAvailability()")
                   && resignObserver.contains("forName: NSWindow.didResignKeyNotification, object: window")
                   && resignObserver.contains("self.owns(window)")
                   && resignObserver.contains("publishMinimalModeCommandAvailability()"),
                   "owned become-key and resign-key events publish eligibility independently")
        guard let fullscreenStart = view.range(of: "private func handleFullScreenEvent("),
              let fullscreenEnd = view.range(of: "private func cancelModeTransitionForFullScreen(",
                                             range: fullscreenStart.upperBound..<view.endIndex) else {
            throw CaseFailure(message: "full-screen command eligibility path is missing", location: "MinimalModeCases")
        }
        let fullscreen = String(view[fullscreenStart.lowerBound..<fullscreenEnd.lowerBound])
        try expect(fullscreen.contains("invalidatePendingGeometryRequests()")
                   && fullscreen.contains("publishMinimalModeCommandAvailability()"),
                   "full-screen transitions cancel measurement and refresh disabled command state")
        try expect(!commands.contains("NotificationCenter.default.post")
                   && context.contains("isMinimalMode = requested"),
                   "mode changes use the live focused binding, not a global broadcast")
    },

    EngineCase("minimal-mode-source-owned-snapshot-latest-request-and-termination-guards") {
        let view = try minimalModeReadSource("Sources/NumlexApp/Views/ContentView.swift")
        guard let begin = view.range(of: "private func beginMinimalModeTransition(to minimal: Bool"),
              let apply = view.range(of: "private func applyModeFrame(",
                                     range: begin.upperBound..<view.endIndex) else {
            throw CaseFailure(message: "mode transition source is missing", location: "MinimalModeCases")
        }
        let beginBlock = String(view[begin.lowerBound..<apply.lowerBound])
        try expect(beginBlock.contains("if normalFrameSnapshot == nil"),
                   "entry captures the real pre-entry frame once")
        try expect(beginBlock.contains("let normalFrame = window.frame")
                   && beginBlock.contains("normalFrameSnapshot = normalFrame"),
                   "entry captures the real original normal frame once")
        try expectEqual(beginBlock.components(separatedBy: "normalFrameSnapshot = normalFrame").count - 1,
                        1, "there is no compact-frame snapshot overwrite")
        try expect(beginBlock.contains("onCaptureNormalFrame?(normalFrame)"),
                   "the one normal snapshot uses the existing rounded writer")
        try expect(beginBlock.contains("from: normalAnchor")
                   && beginBlock.contains("currentFrameSize: frameSize")
                   && beginBlock.contains("currentContentLayoutSize: contentLayoutSize"),
                   "entry is anchored to the cached normal frame and live layout measurement")
        try expect(beginBlock.contains("MinimalModeGeometry.compactFrameSize(")
                   && beginBlock.contains("window.contentLayoutRect.size")
                   && beginBlock.contains("contentView.layoutSubtreeIfNeeded()")
                   && beginBlock.contains("await Task.yield()"),
                   "one next-turn layout task derives the frame from actual contentLayoutRect chrome")
        guard let measuredMinimum = beginBlock.range(of: "if window.minSize != measuredMinimum"),
              let taskClear = beginBlock.range(of: "self.minimalModeMeasurementTask = nil",
                                               range: measuredMinimum.upperBound..<beginBlock.endIndex) else {
            throw CaseFailure(message: "measured minimum completion is missing", location: "MinimalModeCases")
        }
        try expect(beginBlock[measuredMinimum.lowerBound..<taskClear.lowerBound]
                       .contains("guard self.isCurrentModeMeasurement("),
                   "a stale measurement cannot clear a newer owned task")
        try expect(beginBlock.contains("invalidatePendingGeometryRequests()"),
                   "a new transition cancels pending normal settle and sidebar tasks")
        try expect(beginBlock.contains("geometryRequestGeneration &+= 1"),
                   "the transition receives a new generation")
        try expect(view.contains("MinimalModePresentation.isCurrentGeometryRequest("),
                   "every asynchronous frame action checks latest generation and ownership")
        try expect(view.contains("NSAnimationContext.runAnimationGroup"),
                   "the frame animation completion belongs to the coordinator")

        guard let finish = view.range(of: "private func finishModeTransition("),
              let reject = view.range(of: "private func rejectMinimalModeRequest(",
                                      range: finish.upperBound..<view.endIndex) else {
            throw CaseFailure(message: "mode completion source is missing", location: "MinimalModeCases")
        }
        let finishBlock = String(view[finish.lowerBound..<reject.lowerBound])
        try expect(finishBlock.contains("guard isCurrentGeometryRequest(generation, window: window)"),
                   "a stale completion cannot change the snapshot lifetime")
        try expect(finishBlock.contains("if !mode {\n                normalFrameSnapshot = nil")
                   && finishBlock.contains("compactModeMinimumSize = nil"),
                   "only a successful exit consumes the cached normal frame and compact floor")

        guard let settle = view.range(of: "func scheduleFrameSettle(window: NSWindow, immediate: Bool)"),
              let reapply = view.range(of: "func reapply(to window: NSWindow?)",
                                       range: settle.upperBound..<view.endIndex) else {
            throw CaseFailure(message: "normal-frame settle path is missing", location: "MinimalModeCases")
        }
        let settleBlock = String(view[settle.lowerBound..<reapply.lowerBound])
        guard let policyGuard = settleBlock.range(of: "guard owns(window), isWindowReady, mayPersistNormalFrame else { return }"),
              let immediate = settleBlock.range(of: "guard !immediate else {"),
              let immediateWrite = settleBlock.range(of: "onFrameSettled?(window.frame)") else {
            throw CaseFailure(message: "settle policy or termination path is missing", location: "MinimalModeCases")
        }
        try expect(policyGuard.lowerBound < immediate.lowerBound
                   && immediate.lowerBound < immediateWrite.lowerBound,
                   "termination cannot bypass compact/intermediate/full-screen persistence guards")
        try expect(view.contains("toolbarReassertionTask?.cancel()")
                   && view.contains("frameSettleTask?.cancel()")
                   && view.contains("sidebarResizeTask?.cancel()")
                   && view.contains("minimalModeMeasurementTask?.cancel()"),
                   "all owned asynchronous work, including measurement, is canceled")
        try expect(view.contains("for observer in frameObservers + fullScreenObservers")
                   && view.contains("NotificationCenter.default.removeObserver(keyResignObserver)"),
                   "owned window, termination, fullscreen, and resign-key observers are removed")
        guard let owner = view.range(of: "private struct WindowConfigurator"),
              let ownerEnd = view.range(of: "private func applySidebarButtonVisibility(",
                                        range: owner.upperBound..<view.endIndex) else {
            throw CaseFailure(message: "per-window coordinator scope is missing", location: "MinimalModeCases")
        }
        let ownerBlock = String(view[owner.lowerBound..<ownerEnd.lowerBound])
        try expect(ownerBlock.contains("func makeCoordinator() -> Coordinator { Coordinator() }"),
                   "each configurator instance receives its own coordinator")
        try expect(ownerBlock.contains("var normalFrameSnapshot: CGRect?")
                   && ownerBlock.contains("var compactModeMinimumSize: NSSize?")
                   && ownerBlock.contains("var minimalModeMeasurementTask: Task<Void, Never>?"),
                   "normal snapshot, compact minimum, and measurement task are per-coordinator")
        try expect(ownerBlock.contains("compactModeMinimumSize = nil")
                   && ownerBlock.contains("minimalModeMeasurementTask?.cancel()")
                   && ownerBlock.contains("NotificationCenter.default.removeObserver(keyResignObserver)"),
                   "detach clears the per-owner cache, task, and key observer")
        try expect(!ownerBlock.contains("NSApp.keyWindow")
                   && !ownerBlock.contains("NSApp.windows.first"),
                   "no global/foreign window target enters mode geometry")
    },

    EngineCase("minimal-mode-source-editor-and-document-state-remain-presentation-only") {
        let view = try minimalModeReadSource("Sources/NumlexApp/Views/ContentView.swift")
        let settings = try minimalModeReadSource("Sources/NumlexCore/Models/Settings.swift")
        let export = try minimalModeReadSource("Sources/NumlexCore/Export/ExportSnapshotBuilder.swift")
        guard let context = view.range(of: "private var minimalModeCommandContext: MinimalModeCommandContext?"),
              let nextProperty = view.range(of: "/// The native sidebar command talks",
                                            range: context.upperBound..<view.endIndex) else {
            throw CaseFailure(message: "Minimal Mode command binding scope is missing", location: "MinimalModeCases")
        }
        let action = String(view[context.lowerBound..<nextProperty.lowerBound])
        try expect(action.contains("isMinimalMode = requested"),
                   "the menu binding mutates only this ContentView's mode state")
        for mutation in ["model.persist()", "model.settings.showTotalBar =",
                         "model.settings.sidebarVisible =", "model.selectedSheet", "editorBridge",
                         "selectionSnapshot", "setSelectedRange", "clear()"] {
            try expect(!action.contains(mutation),
                       "the command binding does not mutate document/editor state: \(mutation)")
        }
        try expect(view.contains("editorView(sheet: sheet, settings: settings, resolved: resolved)"),
                   "the same editor subtree and resolved input remain mounted")
        try expect(!view.contains(".id(isMinimalMode)"),
                   "mode changes do not rebuild the editor by identity")
        try expect(!view.contains(".onChange(of: isMinimalMode)"),
                   "mode changes do not reset topOffset, metrics, focus, or selection")
        try expect(view.contains("editorBridge?.forwardScrollWheel(event)"),
                   "the editor remains the single scroll source")
        try expect(view.contains("MinimalModePresentation.showTotalBar("),
                   "only the Floating Total boolean is projected")
        try expect(!settings.contains("minimalMode")
                   && !export.contains("minimalMode"),
                   "mode state is absent from settings and export snapshots")
    },
]
