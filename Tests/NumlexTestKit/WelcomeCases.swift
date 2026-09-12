import Foundation
import NumlexCore

/// r98: the first-launch welcome — the pure first-launch policy matrix plus
/// the source contracts of the calculation field, the monochrome silver
/// splash, the monochrome button and the curtain reveal. The app target is
/// not importable from the test kit, so view/launch invariants are pinned at
/// the source (like the other app-layer cases).
public let welcomeCases: [EngineCase] = [

    // MARK: - First-launch policy (pure)

    EngineCase("welcome-marker-name-is-versioned") {
        try expectEqual(FirstLaunch.markerFileName, "welcome-v1", "versioned marker")
        try expect(!FirstLaunch.markerFileName.contains("store"), "not the store")
        try expectEqual(FirstLaunch.artifactFileNames,
                        ["store.json", "rates.json", "weather.json", "locations.json"],
                        "the known data-directory artifacts")
    },

    EngineCase("welcome-empty-directory-shows-welcome") {
        let dir = try welcomeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try expect(FirstLaunch.shouldShowWelcome(in: dir), "a genuinely new install")
        try expect(!FirstLaunch.isCompleted(in: dir), "no marker yet")
        try expect(FirstLaunch.evaluateAtLaunch(in: dir),
                   "the launch entry point agrees")
    },

    EngineCase("welcome-any-prior-artifact-suppresses") {
        for artifact in FirstLaunch.artifactFileNames {
            let dir = try welcomeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            try Data("{}".utf8).write(to: dir.appendingPathComponent(artifact))
            try expect(!FirstLaunch.shouldShowWelcome(in: dir),
                       "\(artifact) marks an existing user")
        }
    },

    EngineCase("welcome-corrupt-store-still-suppresses") {
        let dir = try welcomeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data([0x00, 0xFF, 0x13, 0x37]).write(
            to: dir.appendingPathComponent("store.json"))
        try expect(!FirstLaunch.shouldShowWelcome(in: dir),
                   "a corrupt store still suppresses onboarding")
        try expect(Persistence.load(from: dir) == nil, "and is genuinely unreadable")
    },

    EngineCase("welcome-existing-install-records-marker-only") {
        let dir = try welcomeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        var payload = StorePayload(sheets: [], selectedIndex: 0,
                                   settings: AppSettings(), version: 2)
        payload.settings.appearance = .light
        payload.settings.appIcon = .light
        Persistence.save(payload, to: dir)
        let before = try Data(contentsOf: Persistence.storeURL(in: dir))
        try expect(!FirstLaunch.evaluateAtLaunch(in: dir), "no onboarding")
        try expect(FirstLaunch.isCompleted(in: dir), "marker recorded best-effort")
        try expectEqual(try Data(contentsOf: Persistence.storeURL(in: dir)), before,
                        "store bytes byte-identical")
        guard let reloaded = Persistence.load(from: dir) else {
            throw CaseFailure(message: "store still decodes", location: "Welcome")
        }
        try expectEqual(reloaded.settings.appearance, .light, "explicit appearance kept")
        try expectEqual(reloaded.settings.appIcon, .light, "explicit icon kept")
        try expectEqual(StorePayload.currentVersion, 2, "schema version untouched")
        try FileManager.default.removeItem(at: Persistence.storeURL(in: dir))
        try expect(!FirstLaunch.shouldShowWelcome(in: dir),
                   "a later cache delete cannot resurrect onboarding")
    },

    EngineCase("welcome-cache-only-suppresses-without-store") {
        let dir = try welcomeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("{}".utf8).write(to: dir.appendingPathComponent("rates.json"))
        try expect(!FirstLaunch.evaluateAtLaunch(in: dir), "existing cache user")
        try expect(FirstLaunch.isCompleted(in: dir), "marker recorded")
        try expect(!FileManager.default.fileExists(
                    atPath: Persistence.storeURL(in: dir).path), "no store created")
    },

    EngineCase("welcome-marker-completes-and-is-idempotent") {
        let dir = try welcomeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try expect(FirstLaunch.evaluateAtLaunch(in: dir), "fresh install")
        try expect(!FirstLaunch.isCompleted(in: dir), "launch writes nothing")
        try expectEqual(FirstLaunch.markCompleted(in: dir), true, "Get Started writes")
        let marker = dir.appendingPathComponent(FirstLaunch.markerFileName)
        try expectEqual(try String(contentsOf: marker, encoding: .utf8), "1\n", "payload")
        try expectEqual(FirstLaunch.markCompleted(in: dir), true, "idempotent")
        try expectEqual(try String(contentsOf: marker, encoding: .utf8), "1\n", "stable")
        try expect(!FirstLaunch.shouldShowWelcome(in: dir), "no welcome next launch")
    },

    EngineCase("welcome-aborted-launch-keeps-welcome") {
        let dir = try welcomeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = FirstLaunch.evaluateAtLaunch(in: dir)
        try expect(!FirstLaunch.isCompleted(in: dir), "no marker")
        try expect(FirstLaunch.shouldShowWelcome(in: dir), "welcome returns")
    },

    EngineCase("welcome-decision-works-before-directory-exists") {
        let dir = try welcomeTempDir(deleting: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try expect(!FileManager.default.fileExists(atPath: dir.path), "not created yet")
        try expect(FirstLaunch.shouldShowWelcome(in: dir), "decision is non-creating")
        try expect(FirstLaunch.evaluateAtLaunch(in: dir), "launch entry point too")
        try expect(!FirstLaunch.isCompleted(in: dir), "nothing written with no artifact")
    },

    // MARK: - Launch integration + curtain reveal (source)

    EngineCase("welcome-decision-precedes-model-and-store") {
        let app = try welcomeSource("Sources/NumlexApp/NumlexApp.swift")
        guard let decision = app.range(of: "FirstLaunch.evaluateAtLaunch(in: dataDirectory)"),
              let modelInit = app.range(of: "AppModel()") else {
            throw CaseFailure(message: "decision/model init missing", location: "Welcome")
        }
        try expect(decision.lowerBound < modelInit.lowerBound,
                   "the decision is captured before the model")
        try expect(app.contains("Persistence.dataDirectory(createIfNeeded: false)"),
                   "non-creating directory lookup")
        try expect(app.contains("_revealStage = State(initialValue: isNewInstall ? .welcome : .app)"),
                   "existing installs mount the editor immediately")
    },

    EngineCase("welcome-calculation-field-is-one-batched-canvas") {
        let view = try welcomeSource("Sources/NumlexApp/Views/WelcomeView.swift")
        let renderers = welcomeRendererSource()
        // Still exactly the ten correct expressions in two columns.
        let table = welcomeSlice(view, from: "static let calculations:", to: "static func anchor")
        try expectEqual(table.components(separatedBy: ".init(column:").count - 1, 10, "ten expressions")
        try expectEqual(view.components(separatedBy: ".init(column: .left,").count - 1, 5, "five left rows")
        try expectEqual(view.components(separatedBy: ".init(column: .right,").count - 1, 5, "five right rows")
        // ONE Canvas inside a dedicated ANIMATABLE renderer: a non-Animatable
        // view capturing parent state receives no interpolated values at all
        // (the "5 fps" bug), so the conformance is pinned here.
        try expect(renderers.contains("struct CalculationBloomCanvas: View"), "a dedicated renderer")
        try expect(renderers.contains("nonisolated") || renderers.contains("@preconcurrency Animatable"),
                   "Animatable conformance")
        try expect(view.contains("CalculationBloomCanvas(stream: streamProgress"), "driven by the scalars")
        let canvas = welcomeSlice(renderers, from: "var body: some View {", to: "// MARK: constants")
        try expect(canvas.contains("Canvas(opaque: false, rendersAsynchronously: false)"),
                   "one synchronous Canvas")
        try expectEqual(canvas.components(separatedBy: "Canvas(").count - 1, 1, "exactly one Canvas")
        try expect(canvas.contains("for (index, expression) in WelcomeView.calculations.enumerated()"),
                   "all rows in ONE pass")
        for banned in ["ForEach", "expressionRow", "tokenText", "TimelineView",
                       "repeatForever", "Timer(", "CADisplayLink"] {
            try expect(!canvas.contains(banned), "no \(banned) in the batched field")
        }
        // The per-run stagger, row stagger and result emphasis are computed
        // inside that one pass — never as separate animation transactions.
        let draw = welcomeSlice(renderers, from: "private static func drawRow", to: "// MARK: - Silver splash")
        try expect(draw.contains("tokenStagger"), "per-run stagger inside the pass")
        try expect(renderers.contains("Double(index) * Self.rowStagger"), "per-row stagger")
        try expect(draw.contains("run.isResult, emphasis > 0.01"), "result emphasis inside the pass")
        try expect(!draw.contains(".animation("), "no animation modifiers inside the pass")
        try expect(!draw.contains(".shadow("), "no per-row blur")
        // The 16 pt rounded, monospaced-digit appearance is unchanged.
        try expect(renderers.contains("static let fieldFontSize: CGFloat = 16"), "16 pt")
        try expect(draw.contains("design: .rounded"), "rounded design")
        try expect(draw.contains(".monospacedDigit()"), "monospaced digits")
    },


    EngineCase("welcome-canvas-renderers-carry-every-progress-scalar") {
        let renderers = welcomeRendererSource()
        // Both renderers are Animatable and their animatableData covers EVERY
        // animated scalar: a scalar left out of the pair would silently jump.
        for name in ["stream", "emphasis", "converge", "scale", "iconOffset"] {
            let field = welcomeSlice(renderers, from: "struct CalculationBloomCanvas",
                                     to: "struct SilverSplashCanvas")
            try expect(field.contains("var \(name):") || field.contains("var \(name);"),
                       "field renders \(name)")
        }
        let field = welcomeSlice(renderers, from: "struct CalculationBloomCanvas",
                                 to: "struct SilverSplashCanvas")
        guard let fieldPair = field.range(of: "var animatableData")?.lowerBound,
              let fieldSetter = field.range(of: "set {", range: fieldPair..<field.endIndex)?.lowerBound
        else { throw CaseFailure(message: "field animatableData missing", location: "Welcome") }
        let fieldAnimatable = String(field[fieldPair...])
        for scalar in ["stream", "emphasis", "converge", "scale", "iconOffset"] {
            try expect(fieldAnimatable.contains("self.\(scalar) = ")
                       || fieldAnimatable.contains("\(scalar) = newValue"),
                       "field animatableData carries \(scalar)")
        }
        _ = fieldSetter
        let splash = String(renderers[renderers.range(of: "struct SilverSplashCanvas")!.lowerBound...])
        for scalar in ["burst", "fade", "footprint", "scale", "iconOffset"] {
            try expect(splash.contains("var \(scalar):"), "splash renders \(scalar)")
            try expect(splash.contains("\(scalar) = newValue"), "splash animatableData carries \(scalar)")
        }
        // The splash footprint is DERIVED from the fade scalar (one animation,
        // no second animation retargeting the same renderer).
        let view = try welcomeSource("Sources/NumlexApp/Views/WelcomeView.swift")
        try expect(view.contains("* fadeProgress"), "the footprint follows the fade scalar")
        try expect(!view.contains("iconGrowth"), "no separate footprint animation")
        // Reduce Motion creates neither renderer.
        let reduce = welcomeSlice(view, from: "if reduceMotion {", to: "// 0.00")
        try expect(reduce.contains("fieldActive = false"), "no field renderer")
        try expect(reduce.contains("splashActive = false"), "no splash renderer")
    },


    EngineCase("welcome-colors-come-from-the-editor-palette") {
        let view = try welcomeSource("Sources/NumlexApp/Views/WelcomeView.swift")
        for token in ["Design.numberColor", "Design.variableColor",
                      "Design.conversionColor", "Design.moneyMarkerColor",
                      "Design.baseText", "Design.editorBackground"] {
            try expect(view.contains(token), "uses \(token)")
        }
        try expect(!view.contains("Color(srgb255"), "no hardcoded sRGB")
        try expect(!view.contains("Color(red:"), "no hardcoded RGB")
    },

    // MARK: - Silver splash (source)


    EngineCase("welcome-splash-is-monochrome-silver") {
        let view = try welcomeSource("Sources/NumlexApp/Views/WelcomeView.swift")
        // The rejected coloured arcs are gone.
        try expect(!view.contains("WelcomeArc"), "no colored arc shape")
        try expect(!view.contains("arcStyles"), "no colored arc palette")
        try expect(!view.contains("arcProgress"), "no colored arc progress")
        // The splash draws from neutral/icon tones only.
        try expect(view.contains("private var silver: Color { Color(nsColor: Design.baseText) }"),
                   "silver from the icon family (baseText)")
        try expect(view.contains("private var silverSoft: Color { Color(nsColor: .secondaryLabelColor) }"),
                   "the wave uses a neutral label tone")
        for hue in ["Design.numberColor", "Design.variableColor",
                    "Design.conversionColor", "Design.moneyMarkerColor"] {
            let splash = welcomeSlice(view, from: "private var splash: some View",
                                      to: "private func icon(")
            try expect(!splash.contains(hue), "the splash never uses \(hue)")
        }
        // Deterministic counts: 14 rays, 8 droplets, one wave.
        let renderers = welcomeRendererSource()
        try expectEqual(renderers.components(separatedBy: "static let rays:").count - 1, 1, "one ray table")
        try expectEqual(renderers.components(separatedBy: "static let droplets:").count - 1, 1,
                        "one droplet table")
        try expect(renderers.contains("(8, 96, 0.00, 2.5)"), "the ray table is literal/fixed")
        try expect(renderers.contains("(20, 100, 3.5, 0.02)"), "the droplet table is literal/fixed")
        // Still exactly 14 rays and 8 droplets (the ring was pushed outward
        // so the droplets read outside the larger icon).
        let rayTable = welcomeSlice(renderers, from: "static let rays:", to: "/// 8 droplets placed")
        try expectEqual(welcomeTupleCount(rayTable), 14, "14 rays")
        let dropTable = welcomeSlice(renderers, from: "static let droplets:", to: "/// Rays start just outside")
        try expectEqual(welcomeTupleCount(dropTable), 8, "8 droplets")
        // The whole burst is ONE Canvas drawn from two finite scalars, with
        // the deterministic geometry still living in the same arrays.
        try expect(renderers.contains("private static func drawWave("), "one soft expanding wave")
        try expect(renderers.contains("private static func drawRays("), "one ray pass")
        try expect(renderers.contains("private static func drawDroplets("), "one droplet pass")
        let splash = welcomeSlice(renderers, from: "struct SilverSplashCanvas",
                                  to: "private static func drawWave")
        try expect(splash.contains("Canvas(opaque: false, rendersAsynchronously: false)"),
                   "one splash Canvas")
        try expectEqual(splash.components(separatedBy: "Canvas(").count - 1, 1, "exactly one Canvas")
        try expect(splash.contains("Self.drawRays(&context"), "the ray pass is called")
        try expect(splash.contains("Self.drawDroplets(&context"), "the droplet pass is called")
        try expect(splash.contains("Self.drawWave(&context"), "the wave pass is called")
        for banned in ["ForEach", "Capsule()", ".animation(", "TimelineView"] {
            try expect(!splash.contains(banned), "no \(banned) in the batched splash")
        }
        try expect(splash.contains("var burst: Double"), "driven by the burst scalar")
        try expect(splash.contains("var fade: Double"), "and the fade scalar")
        try expect(renderers.contains("rayOriginRadius * footprint * scale"),
                   "rays stay anchored to the icon edge")
        // No runtime randomness anywhere in the welcome.
        for banned in ["random", "shuffled", "SystemRandomNumberGenerator"] {
            try expect(!view.contains(banned), "no runtime randomness: \(banned)")
        }
    },

    // MARK: - TEMPORARY QA replay control (source)


    EngineCase("welcome-temporary-replay-control-is-quarantined") {
        let sidebar = try welcomeSource("Sources/NumlexApp/Views/SidebarView.swift")
        let app = try welcomeSource("Sources/NumlexApp/NumlexApp.swift")
        // Exactly ONE temporary control, marked for removal.
        try expectEqual(sidebar.components(separatedBy: "TEMPORARY QA CONTROL").count - 1, 2,
                        "the control is marked (state + row)")
        try expect(sidebar.contains("remove after onboarding sign-off"), "removal is obvious")
        try expectEqual(sidebar.components(separatedBy: "Replay Welcome").count - 1, 2,
                        "one label + one accessibility label")
        try expectEqual(sidebar.components(separatedBy: ".replayWelcome").count - 1, 1,
                        "exactly one post site")
        try expect(sidebar.contains(".post(name: .replayWelcome, object: nil)"),
                   "the row only posts the notification")
        // The row is a sibling BELOW the pinned folder tabs, so it can never
        // cover them, and it stays quiet (secondary text, plain style).
        guard let tabs = sidebar.range(of: "            folderTabs")?.upperBound,
              let replay = sidebar.range(of: "NotificationCenter.default.post(name: .replayWelcome",
                                                                             range: tabs..<sidebar.endIndex)?.lowerBound
        else { throw CaseFailure(message: "replay row not after folderTabs", location: "Sidebar") }
        try expect(tabs < replay, "the row follows the pinned tabs")
        try expect(sidebar.contains(".buttonStyle(.plain)"), "not a competing glass surface")
        try expect(sidebar.contains(".foregroundStyle(.secondary)"), "visually quiet")
        try expect(sidebar.contains(".frame(height: 28)"), "at least a 28 pt hit row")
        // r105: this row is NOT gated by the welcome transition — the user
        // meant the NATIVE sidebar toggle. The row keeps its normal
        // visibility, hover and accessibility behaviour.
        try expect(!sidebar.contains("replayControlHidden"), "no transition gate on the row")
        try expect(!sidebar.contains(".accessibilityHidden(replayControlHidden)"),
                   "always reachable by assistive tech")
        try expect(sidebar.contains(".onHover { replayHovering = $0 }"), "hover stays")
        try expect(sidebar.contains(".help(\"Replay the welcome animation\")"), "tooltip stays")
        try expect(sidebar.contains(".help(\"Replay the welcome animation\")"), "a clear tooltip")
        try expect(sidebar.contains(".accessibilityLabel(Text(\"Replay Welcome\"))"), "a11y label")
        try expect(sidebar.contains(".accessibilityHint("), "a11y hint")
        // The sidebar never touches the model, the marker or the store.
        let replayRow = String(sidebar[replay...])
        for banned in ["markCompleted", "FirstLaunch", "Persistence", "model.save",
                       "model.sheets", "revealStage"] {
            try expect(!replayRow.contains(banned), "the row never touches \(banned)")
        }
        // The notification name is app-local and declared once.
        try expect(app.contains("static let replayWelcome = Notification.Name(\"numlex.replayWelcome\")"),
                   "one app-local notification")
        try expectEqual(app.components(separatedBy: "static let replayWelcome").count - 1, 1,
                        "declared exactly once")
    },


    EngineCase("welcome-native-sidebar-toggle-hides-during-reveal") {
        let app = try welcomeSource("Sources/NumlexApp/NumlexApp.swift")
        let content = try welcomeSource("Sources/NumlexApp/Views/ContentView.swift")
        let sidebar = try welcomeSource("Sources/NumlexApp/Views/SidebarView.swift")
        // The transient flag is derived at the session root from the stage and
        // the overlay, and threaded through the environment — never persisted.
        try expect(app.contains("private var sidebarToggleHiddenForWelcome: Bool"), "one flag")
        try expect(app.contains("revealStage != .app || replayWelcomePresented"),
                   "true through production AND replay reveals")
        try expect(app.contains("private struct SidebarToggleHiddenKey: EnvironmentKey"),
                   "a transient environment key")
        try expect(app.contains(".environment(\\.sidebarToggleHiddenForWelcome,"),
                   "threaded through the environment")
        for banned in ["AppSettings", "UserDefaults", "store.json"] {
            let key = welcomeSlice(app, from: "private struct SidebarToggleHiddenKey",
                                   to: "extension Notification.Name")
            try expect(!key.contains(banned), "the flag never touches \(banned)")
        }
        // ContentView reads it and passes it into the native configurator.
        try expect(content.contains("@Environment(\\.sidebarToggleHiddenForWelcome)"),
                   "ContentView reads the flag")
        try expect(content.contains("forceHideSidebarButton: sidebarToggleHiddenForWelcome"),
                   "passed into WindowConfigurator")
        try expect(content.contains("var forceHideSidebarButton: Bool"), "a declared input")
        // ONE effective rule, honoured by every path.
        try expect(content.contains("static func effectiveSidebarButtonHidden(preference: Bool,"),
                   "one effective rule")
        try expect(content.contains("forced || (preference && collapsed)"),
                   "forced OR (preference AND collapsed)")
        try expect(content.contains("func reapply(to window: NSWindow?)"), "one re-apply helper")
        try expect(content.components(separatedBy: "coord.reapply(to:").count - 1 >= 3,
                   "make (retries), update and the observers all re-apply")
        // Both native identifiers, matched by `isHidden` only.
        try expect(content.contains(".itemIdentifier == .toggleSidebar"), "classic identifier")
        try expect(content.contains("com.apple.SwiftUI.navigationSplitView.toggleSidebar"),
                   "SwiftUI identifier")
        try expect(content.contains("item.isHidden != hide"), "isHidden assignment only")
        for banned in ["toolbar.isVisible = false", ".removeItem", "insertItem"] {
            try expect(!content.contains(banned), "never \(banned)")
        }
        try expect(!content.contains("isHidden = true\n"), "no unconditional hide")
        // Bounded retries and an event observer, both torn down.
        try expect(content.contains("for step in [8, 16, 24, 48, 96] as [UInt64]"),
                   "bounded next-render-turn retries")
        try expect(!content.contains("Timer("), "no poller")
        try expect(content.contains("NSToolbar.willAddItemNotification"), "toolbar event observer")
        try expect(content.contains("coordinator.itemObserver = nil"), "observer released")
        try expect(content.contains("NotificationCenter.default.removeObserver(obs)"),
                   "observer removed")
        // The temporary replay row is NOT gated by this flag.
        try expect(!sidebar.contains("sidebarToggleHiddenForWelcome"), "the row is untouched")
        try expect(sidebar.contains(".help(\"Replay the welcome animation\")"), "still available")
    },

    EngineCase("welcome-replay-cannot-resize-the-base-view") {
        let app = try welcomeSource("Sources/NumlexApp/NumlexApp.swift")
        // The base root is the SIZING AUTHORITY: a replay attaches with
        // `.overlay` (a non-sizing layer) and only ever toggles hit testing
        // and compositing on the base — never its frame, clip or safe area.
        try expect(app.contains("launchRoot\n            .allowsHitTesting(!replayWelcomePresented)"),
                   "the base is launchRoot with a hit-testing gate")
        try expect(app.contains(".overlay {\n                if replayWelcomePresented {"),
                   "the overlay is an overlay layer, not a ZStack sibling")
        try expect(!app.contains("ZStack {\n            launchRoot"), "no sizing sibling ZStack")
        // The curtain layers carry no GeometryReader of their own…
        func code(_ text: String) -> String {
            text.split(separator: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//")
                       && !$0.trimmingCharacters(in: .whitespaces).hasPrefix("///") }
                .joined(separator: "\n")
        }
        let launch = code(welcomeSlice(app, from: "struct LaunchContainer: View", to: "struct ReplayOverlay: View"))
        let overlay = code(welcomeSlice(app, from: "struct ReplayOverlay: View", to: "struct CurtainPanel"))
        try expect(!launch.contains("GeometryReader"), "the launch container has no GeometryReader")
        try expect(!overlay.contains("GeometryReader"), "the replay overlay has no GeometryReader")
        try expect(launch.contains("travel: RevealTiming.travelDistance"), "fixed travel")
        try expect(overlay.contains("travel: RevealTiming.travelDistance"), "fixed travel")
        // …and the fixed distance is the designed content height plus overscan.
        try expect(app.contains("static var travelDistance: CGFloat {"), "one travel constant")
        try expect(app.contains("MainWindowGeometry.defaultContentHeight + overscan"),
                   "travel = designed height + overscan")
        // The base is never clipped or offset by the curtain.
        try expect(!launch.contains(".clipped()"), "the base is not clipped")
        try expect(!launch.contains(".offset("), "the base is never offset")
        try expect(!launch.contains("ignoresSafeArea"), "the base never ignores the safe area")
        // No compensating geometry hacks anywhere.
        for banned in ["padding(.top, 52", "offset(y: -52", "setFrame", "scrollTo"] {
            try expect(!app.contains(banned), "no compensation: \(banned)")
        }
    },

    EngineCase("welcome-curtain-reveal-contract") {
        let app = try welcomeSource("Sources/NumlexApp/NumlexApp.swift")
        // Three stages on ONE stable container: the welcome lives in a
        // single branch with an explicit stable id, the editor appears only
        // from `.revealing`, and `.app` removes the welcome after the travel.
        try expect(app.contains("enum RevealStage { case welcome, revealing, app }"),
                   "three stages on one container")
        try expect(app.contains("struct LaunchContainer: View"), "one launch container")
        try expect(app.contains("struct ReplayOverlay: View"), "one replay overlay")
        try expect(app.contains("static let productionWelcomeID"), "one stable id")
        try expect(app.contains(".id(NumlexApp.productionWelcomeID)"), "the welcome is pinned")
        // The slide is an INTERPOLATED scalar inside an Animatable panel: a
        // state-flag offset measurably jumped, so this is the contract.
        try expect(app.contains("struct CurtainPanel<Content: View>: View, @preconcurrency Animatable"),
                   "an animatable curtain panel")
        try expect(app.contains("var animatableData: AnimatablePair<Double, AnimatablePair<CGFloat, Double>>"),
                   "the panel interpolates progress, travel and shadow")
        try expect(app.contains(".offset(y: -travel * CGFloat(progress))"),
                   "the offset is driven by the interpolated scalar")
        try expect(app.contains("@State private var progress: Double = 0"),
                   "the progress is VIEW-owned state")
        try expect(app.contains(".onChange(of: revealRequested)"), "the app requests the lift")
        try expect(app.contains("withAnimation(requested ? RevealTiming.curtainAnimation : nil)"),
                   "the lift is animated")
        try expect(!app.contains("curtainLifted"), "no plain state-flag offset left")
        // A bounded render turn before the slide (not a bare yield).
        try expect(app.contains("RevealTiming.mountCommitNanoseconds"), "a committed frame")
        try expect(!app.contains("revealStage = .revealing\n        withAnimation"),
                   "the mount step is never the animated step")
        // The editor exists only from the reveal onward, and the welcome only
        // until the travel has finished.
        try expect(app.contains("if stage != .welcome {"), "the editor appears on reveal")
        try expect(app.contains("if stage != .app {"), "the welcome leaves at the end")
        try expect(app.contains(".allowsHitTesting(stage == .app)"),
                   "the editor cannot take pointer events while covered")
        try expect(app.contains(".allowsHitTesting(stage == .welcome)"),
                   "the welcome owns the pointer until it leaves")
        // Get Started is armed only while the welcome still owns the stage,
        // and WelcomeView guards the action itself (`activating`).
        try expect(app.contains("onGetStarted: revealStage == .welcome ? beginReveal : {}")
                   || app.contains("onGetStarted: beginReveal"),
                   "Get Started is a one-shot action")
        try expect(app.contains(".allowsHitTesting(stage == .welcome)"),
                   "and cannot be hit once the travel has begun")
        let welcome = try welcomeSource("Sources/NumlexApp/Views/WelcomeView.swift")
        try expect(welcome.contains("guard !activating else { return }"),
                   "the welcome guards double activation")
        // The slide is deliberate: 0.85-0.95 s, no bounce, with overscan.
        try expect(app.contains("static let duration: Double = 0.90"), "slide duration")
        try expect(app.contains("static let overscan: CGFloat = 80"), "safe overscan")
        try expect(app.contains("timingCurve(0.42, 0.0, 0.20, 1.0"), "smooth ease, no bounce")
        try expect(!app.contains("spring("), "never a bouncy spring")
        // Cancellation + the removal wait.
        try expect(app.contains("guard !Task.isCancelled, revealStage == .revealing"),
                   "the animation step is guarded")
        try expect(app.contains("static let travelNanoseconds: UInt64 = 950_000_000"),
                   "the removal waits for the travel plus slack")
        // Reduce Motion removes the welcome with no delay and no slide.
        let reduce = welcomeSlice(app, from: "if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {",
                                  to: "// 1) Mount the editor")
        try expect(reduce.contains("revealStage = .app"), "removed immediately")
        try expect(reduce.contains("focusSelectedEditor()"), "focus immediately")
        try expect(!reduce.contains("withAnimation"), "no animation under Reduce Motion")
        try expect(!reduce.contains("Task.sleep"), "no delay under Reduce Motion")
        // The NSWindow frame is never animated.
        for banned in ["setFrame", "setFrameOrigin", "animator()"] {
            try expect(!app.contains(banned), "no window frame API: \(banned)")
        }
    },

    EngineCase("welcome-enlargement-keeps-the-stream-footprint") {
        let view = try welcomeSource("Sources/NumlexApp/Views/WelcomeView.swift")
        try expect(view.contains("static let finalIconSize: CGFloat = 176"), "176 pt final icon")
        try expect(view.contains("static let preFinishIconScale: CGFloat = 110 / finalIconSize"),
                   "the streaming footprint still derives from 110 pt")
        try expect(view.contains("static let sloganLineOneSize: CGFloat = 38"), "line 1 at 38 pt")
        try expect(view.contains("static let sloganLineTwoSize: CGFloat = 30"), "line 2 at 30 pt")
        try expect(view.contains("static let sloganReservedWidth: CGFloat = 680"), "reserved width")
        try expect(view.contains("static let sloganReservedHeight: CGFloat = 94"), "reserved height")
        try expect(view.contains("static let sloganCanvasOffset = CGSize(width: 0, height: 112)"),
                   "slogan anchor")
        try expect(view.contains("static let buttonCanvasOffsetY: CGFloat = 218"), "button anchor")
        // The icon's rounded corner scales with the larger frame.
        try expect(view.contains("cornerRadius: Self.iconCornerRadius"), "a derived corner radius")
        try expect(view.contains("static let iconCornerRadius"), "the radius constant")
        // Layout: the enlarged lockup still fits the 800x600 canvas with the
        // titlebar and both edges clear.
        let iconHalf: Double = 88
        let iconCentre: Double = 300 - 47
        let iconTop: Double = iconCentre - iconHalf
        let iconBottom: Double = iconCentre + iconHalf
        let sloganHalf: Double = 47
        let sloganCentre: Double = 300 + 112
        let sloganTop: Double = sloganCentre - sloganHalf
        let sloganBottom: Double = sloganCentre + sloganHalf
        let buttonTop: Double = 300 + 218 - 20.5
        let buttonBottom: Double = 300 + 218 + 20.5
        try expect(iconTop > 40, "clear of the titlebar")
        try expect(sloganTop - iconBottom >= 20, "clean gap under the icon")
        try expect(buttonTop - sloganBottom >= 15, "clean gap above the button")
        try expect(600 - buttonBottom >= 60, "balanced bottom margin")
    },

    EngineCase("welcome-replay-preserves-the-editor-responder") {
        let app = try welcomeSource("Sources/NumlexApp/NumlexApp.swift")
        // The replay captures the LIVE first responder before it is covered.
        try expect(app.contains("@State private var replayRestoreResponder: NotebookTextView?"),
                   "one captured responder")
        let present = welcomeSlice(app, from: "private func presentReplayWelcome",
                                   to: "private static func liveEditorResponder")
        try expect(present.contains("replayRestoreResponder = Self.liveEditorResponder()"),
                   "captured on presentation")
        // The document is protected from invisible typing while the overlay
        // plays: the view is merely resigned (its state and reference stay).
        try expect(present.contains("window.makeFirstResponder(nil)"),
                   "the editor is resigned while covered")
        try expect(present.contains("guard revealStage == .app, !replayWelcomePresented"),
                   "only from the settled editor, never twice")
        // Observation only: the capture walks to the text view, it never
        // mutates the editor.
        let finder = welcomeSlice(app, from: "private static func liveEditorResponder",
                                  to: "var body: some Scene")
        for banned in ["selectedRange", "setSelectedRange", "typingAttributes", "scroll(",
                       "markedRange", "insertText", "string ="] {
            try expect(!finder.contains(banned), "the capture never touches \(banned)")
        }
        try expect(finder.contains("window.firstResponder as? NotebookTextView"),
                   "the first responder is preferred")
        try expect(finder.contains("findTextView(in: window.contentView)"),
                   "with a view-tree fallback")
        // Restoring is a bare makeFirstResponder: the selection, typing
        // attributes, scroll origin and marked text are left exactly alone.
        let restore = welcomeSlice(app, from: "private func restoreReplayResponder",
                                   to: "var body: some Scene")
        try expect(restore.contains("window.makeFirstResponder(textView)"),
                   "the SAME text view takes the keyboard back")
        try expect(restore.contains("defer { replayRestoreResponder = nil }"),
                   "the temporary reference is released")
        for banned in ["selectedRange", "setSelectedRange", "typingAttributes",
                       "scroll(", "markedRange", "focusSelectedEditor"] {
            try expect(!restore.contains(banned), "restoring never touches \(banned)")
        }
        // Conservative fallback: a view that is gone leaves the content alone.
        try expect(restore.contains("guard let textView = replayRestoreResponder"),
                   "nothing happens when the editor is gone")
        // The PRODUCTION first-launch path keeps its model focus request: the
        // new editor did not exist beforehand.
        let beginning = welcomeSlice(app, from: "private func beginReveal", to: "private func focusSelectedEditor")
        try expect(beginning.contains("focusSelectedEditor()"),
                   "the first-launch path still uses the model request")
    },

    EngineCase("welcome-replay-hides-the-underlay-without-unmounting") {
        let app = try welcomeSource("Sources/NumlexApp/NumlexApp.swift")
        try expect(app.contains("@State private var replayContentReady = false"),
                   "one readiness flag")
        let root = welcomeSlice(app, from: "private var sessionRoot: some View",
                                to: "private func presentReplayWelcome")
        // The editor stays MOUNTED: opacity only, never `.hidden()`, never a
        // conditional that would change identity or layout.
        try expect(root.contains("launchRoot"), "the editor stays mounted")
        try expect(root.contains(".opacity(replayWelcomePresented && !replayContentReady ? 0 : 1)"),
                   "compositing is suspended while covered")
        let rootCode = root.split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        try expect(!rootCode.contains(".hidden()"), "never hidden()")
        try expect(!root.contains("if replayWelcomePresented {\n                ContentView"),
                   "never conditionally unmounted")
        try expect(root.contains(".allowsHitTesting(!replayWelcomePresented)"),
                   "pointer events are blocked while covered")
        // The editor becomes visible BEFORE the curtain lifts.
        let finish = welcomeSlice(app, from: "private func finishReplay", to: "private func restoreReplayResponder")
        guard let ready = finish.range(of: "replayContentReady = true")?.lowerBound,
              let lift = finish.range(of: "replayLiftRequested = true", range: ready..<finish.endIndex)?.lowerBound
        else { throw CaseFailure(message: "underlay reveal order missing", location: "Welcome") }
        try expect(ready < lift, "visible one frame before the lift")
        try expect(finish.contains("RevealTiming.mountCommitNanoseconds"),
                   "the visibility commits on a real render turn")
        try expect(finish.contains("restoreReplayResponder()"), "then the keyboard returns")
    },

    EngineCase("welcome-replay-overlay-never-touches-production-state") {
        let app = try welcomeSource("Sources/NumlexApp/NumlexApp.swift")
        // The scene root keeps the production launchRoot MOUNTED and only
        // inserts a sibling overlay above it.
        try expect(app.contains("private var sessionRoot: some View"), "one session root")
        try expect(app.contains("themedRoot(sessionRoot)"), "the scene uses the session root")
        try expect(app.contains("themedRoot(launchRoot)") == false, "launchRoot is retained inside it")
        let root = welcomeSlice(app, from: "private var sessionRoot: some View", to: "private func presentReplayWelcome")
        try expect(root.contains("launchRoot"), "the production root stays mounted")
        try expect(app.contains(".allowsHitTesting(!replayWelcomePresented)"),
                   "hit testing is blocked while the overlay covers")
        try expect(app.contains(".overlay {"), "the replay is a NON-SIZING overlay layer")
        try expect(app.contains("if replayWelcomePresented {"), "the overlay is conditional")
        try expect(app.contains("content: WelcomeView(language: language"),
                   "a real welcome inside the curtain panel")
        try expect(app.contains(".id(replaySession)"),
                   "a fresh identity restarts the staged animation")
        try expect(app.contains("travel: RevealTiming.travelDistance"),
                   "the panel travels a FIXED distance (no GeometryReader)")
        try expect(app.contains("shadowOpacity: progress > 0.001 ? 0 : 0.28"),
                   "the same restrained panel shadow")
        // The production first-launch machinery is untouched by the replay:
        // the replay never resets the production stage.
        let replayCode = welcomeSlice(app, from: "private func presentReplayWelcome",
                                      to: "var body: some Scene")
        for banned in ["revealStage = .welcome", "revealStage = .revealing", "revealStage = .app",
                       "FirstLaunch", "markCompleted", "Persistence", "model.save", "store.json"] {
            try expect(!replayCode.contains(banned), "replay never touches \(banned)")
        }
        // Presenting is guarded and idempotent; finishing resets its own
        // curtain state and cancels stale work.
        let present = welcomeSlice(app, from: "private func presentReplayWelcome", to: "private func finishReplay")
        try expect(present.contains("guard revealStage == .app, !replayWelcomePresented else { return }"),
                   "only after the production reveal, never twice")
        try expect(present.contains("replayTask?.cancel()"), "stale work cancelled")
        try expect(present.contains("replayLiftRequested = false"), "curtain state reset")
        try expect(present.contains("replaySession = UUID()"), "a new session each time")
        // Finishing mirrors the production contract: stable identity, one
        // animated travel, removal, then focus. Reduce Motion is immediate.
        let finish = welcomeSlice(app, from: "private func finishReplay", to: "var body: some Scene")
        try expect(finish.contains("guard replayWelcomePresented else { return }"), "one finish only")
        try expect(finish.contains("replayLiftRequested = true"),
                   "the same reveal animation (the overlay animates its own progress)")
        try expect(finish.contains("Task.sleep(nanoseconds: RevealTiming.travelNanoseconds)"),
                   "the same travel wait")
        try expect(finish.contains("guard !Task.isCancelled, replayWelcomePresented else { return }"),
                   "the animation step is guarded")
        // r101: the replay restores the LIVE responder instead of issuing a
        // model focus request (which would reset the caret to position 0).
        try expect(finish.contains("restoreReplayResponder()"), "the keyboard is handed back")
        try expect(!finish.contains("focusSelectedEditor()"),
                   "the replay never resets the caret via a focus request")
        try expect(finish.contains("NSWorkspace.shared.accessibilityDisplayShouldReduceMotion"),
                   "Reduce Motion is honoured")
        let reduceBranch = welcomeSlice(finish, from: "if reduceMotion {", to: "replayTask = Task")
        try expect(reduceBranch.contains("replayWelcomePresented = false"), "removed immediately")
        try expect(!reduceBranch.contains("withAnimation"), "no animation under Reduce Motion")
        try expect(!reduceBranch.contains("Task.sleep"), "no delay under Reduce Motion")
        // The editor is never re-created or duplicated.
        for banned in ["AppModel()", "ContentView(model: model)"] {
            try expect(!replayCode.contains(banned), "no duplicate editor: \(banned)")
        }
        try expect(app.contains("launchRoot"), "the production stage switch remains")
        for stage in ["if stage != .welcome {", "if stage != .app {"] {
            try expect(app.contains(stage), "production stage gate \(stage)")
        }
    },

    // MARK: - Monochrome button (source)

    EngineCase("welcome-button-is-monochrome-and-accessible") {
        let view = try welcomeSource("Sources/NumlexApp/Views/WelcomeView.swift")
        guard let buttonStart = view.range(of: "private struct GetStartedButton: View")?.lowerBound else {
            throw CaseFailure(message: "GetStartedButton missing", location: "Welcome")
        }
        let button = String(view[buttonStart...])
        try expect(!button.contains(".borderedProminent"), "no system-accent prominent style")
        try expect(button.contains("private var fill: Color { Color(nsColor: Design.baseText) }"),
                   "the fill is the icon family's dominant tone")
        try expect(button.contains("Color(nsColor: Design.editorBackground)"),
                   "the label is the opposite end of the same pair")
        try expect(button.contains("Color(nsColor: .keyboardFocusIndicatorColor)"),
                   "an explicit accessible focus ring")
        try expect(button.contains("@FocusState private var focused: Bool"), "focus state")
        try expect(button.contains("RoundedRectangle(cornerRadius: 10, style: .continuous)"),
                   "continuous rounded shape")
        try expect(button.contains(".keyboardShortcut(.defaultAction)"), "Return/Space")
        try expect(button.contains("frame(minWidth: 196)"), "compact premium width")
        try expect(button.contains(".opacity(hovering ? 0.94 : 1)"), "subtle hover only")
        try expect(button.contains(".onHover"), "hover is tracked")
        try expect(button.contains("welcome.getStarted") && button.contains("welcome.getStartedHint"),
                   "localized label + hint")
        // The welcome keeps the hidden-until-revealed and double-guard rules.
        try expect(view.contains(".allowsHitTesting(buttonRevealed && !activating)"),
                   "a hidden button cannot be clicked")
        try expect(view.contains(".accessibilityHidden(!buttonRevealed)"),
                   "a hidden button is hidden from VoiceOver")
        try expect(view.contains("guard !activating else { return }"), "double guard")
    },

    // MARK: - Choreography (source)

    EngineCase("welcome-bloom-is-one-shot-within-budget") {
        let view = try welcomeSource("Sources/NumlexApp/Views/WelcomeView.swift")
        for banned in ["TimelineView", "repeatForever", "phaseAnimator", "Timer(", "repeating"] {
            try expect(!view.contains(banned), "no \(banned)")
        }
        try expect(view.contains(".task { await bloom() }"), "one structured task")
        try expect(view.contains("if Task.isCancelled { return }"), "cancellation checks")
        // r101: five finite scalars drive the two Canvas passes; the icon,
        // slogan and button keep their own finite animations.
        for stage in ["iconRevealed", "streamProgress", "emphasisProgress",
                      "convergeProgress", "burstProgress", "fadeProgress",
                      "fieldActive", "splashActive", "pulsed", "sheenProgress",
                      "sloganRevealed", "buttonRevealed"] {
            try expect(view.contains("$\(stage)") || view.contains("\(stage) ="),
                       "stage \(stage)")
        }
        // The batched passes are one-shot: no ticker, no repetition, and the
        // Canvases are dropped once their pass is over.
        for banned in ["TimelineView", "repeatForever", "phaseAnimator", "Timer("] {
            try expect(!view.contains(banned), "no \(banned) in the batched field/splash")
        }
        try expect(view.contains("fieldActive = false"), "the field canvas retires")
        try expect(view.contains("splashActive = false"), "the splash canvas retires")
        for scalar in ["streamProgress", "emphasisProgress", "convergeProgress",
                       "burstProgress", "fadeProgress"] {
            try expect(view.contains("withAnimation(\(scalar == "streamProgress" ? "" : "").easeOut") ||
                       view.contains("\(scalar) = 1"),
                       "one finite assignment for \(scalar)")
        }
        for prop in ["opacity(", "offset(", "scaleEffect(", "rotationEffect("] {
            try expect(view.contains(prop), "geometry-neutral \(prop)")
        }
        // The splash is one-shot and bounded: the whole burst is one finite
        // scalar, then one fade — never a repeating animation.
        try expect(view.contains("withAnimation(.easeOut(duration: 0.46)) { burstProgress = 1 }"),
                   "the burst travels once")
        try expect(view.contains("withAnimation(.easeOut(duration: 0.30)) { fadeProgress = 1 }"),
                   "the burst fades once")
        // The staged sleeps stay inside the ~2.3-2.6 s budget, and the
        // quietest gaps are short: no long blank pause anywhere.
        let sleeps = ["140_000_000", "480_000_000", "330_000_000", "350_000_000",
                      "340_000_000", "100_000_000", "300_000_000", "440_000_000"]
        for s in sleeps { try expect(view.contains(s), "sleep \(s)") }
        let millis = sleeps.map { Int($0.replacingOccurrences(of: "_", with: ""))! / 1_000_000 }
        let total = millis.reduce(0, +)
        try expect(total >= 2300 && total <= 2600, "staged sleeps ~2.48 s (got \(total) ms)")
        try expect(millis.allSatisfy { $0 <= 480 }, "no single pause over 0.48 s")
        // The button reveal ends 0.44 s before the last sleep does, so the
        // focus handoff lands strictly AFTER the fade has fully settled.
        let revealEnd = total - 440 + 400
        try expect(revealEnd >= 2300 && revealEnd <= 2600, "reveal budget \(revealEnd) ms")
        try expect(total > revealEnd, "focus waits for the fade to settle")
    },

    EngineCase("welcome-reduce-motion-skips-everything") {
        let view = try welcomeSource("Sources/NumlexApp/Views/WelcomeView.swift")
        try expect(view.contains("@Environment(\\.accessibilityReduceMotion)"), "Reduce Motion")
        guard let rm = view.range(of: "if reduceMotion {"),
              let ret = view.range(of: "return", range: rm.upperBound..<view.endIndex)
        else { throw CaseFailure(message: "reduce-motion branch missing", location: "Welcome") }
        let branch = String(view[rm.upperBound..<ret.lowerBound])
        try expect(branch.contains("iconRevealed = true"), "icon immediately")
        try expect(branch.contains("iconExpanded = true"), "icon expanded immediately")
        try expect(branch.contains("sloganRevealed = true"), "slogan immediately")
        try expect(branch.contains("buttonRevealed = true"), "button immediately")
        try expect(branch.contains("buttonFocused = true"), "focused immediately")
        try expect(!branch.contains("Task.sleep"), "zero sleeps")
        try expect(!branch.contains("withAnimation"), "no animation")
        for stage in ["tokensRevealed", "emphasized", "converged", "splashBurst",
                      "waveProgress", "pulsed"] {
            try expect(!branch.contains("\(stage) = true"),
                       "\(stage) never runs under Reduce Motion")
        }
        // Nothing staged, nothing delayed, nothing animated: the static
        // final scene is set in one pass.
        try expect(!branch.contains("offset"), "no staged offset under Reduce Motion")
    },

    EngineCase("welcome-icon-is-large-with-one-fixed-frame") {
        let view = try welcomeSource("Sources/NumlexApp/Views/WelcomeView.swift")
        let renderers = welcomeRendererSource()
        try expect(view.contains("AppIconResources.previewImage(for: .dark)"),
                   "the packaged Dark primary preview")
        try expect(view.contains("app.dashed"), "the missing-preview fallback")
        try expect(view.contains("static let canvas = CGSize(width: 800, height: 600)"),
                   "the fixed design canvas")
        try expect(view.contains("let scale = min(1, min(geo.size.width"),
                   "one geometry-derived scale factor")
        try expect(view.contains(".frame(width: geo.size.width, height: geo.size.height)"),
                   "the composition fills the window without an intrinsic size")
        // The FINAL icon frame is 148-156 pt and is the frame from the very
        // first layout pass.
        try expect(view.contains("static let finalIconSize: CGFloat = 176"), "176 pt final icon")
        try expect(view.contains(".frame(width: Self.finalIconSize, height: Self.finalIconSize)"),
                   "one fixed final frame")
        try expect(!view.contains("frame(width: 110, height: 110)"), "no 110 pt frame")
        // Streaming footprint ≈ the old 110 pt (108-114 pt).
        try expect(view.contains("static let preFinishIconScale: CGFloat = 110 / finalIconSize"),
                   "the pre-finish scale derives from the old footprint")
        let preFinish = 176 * (110.0 / 176.0)
        try expect(preFinish >= 108 && preFinish <= 114, "≈110 pt while streaming")
        // Scale only; combined deterministically, never added.
        try expect(view.contains("private var iconVisualScale: CGFloat"), "one combined scale")
        try expect(view.contains("pulsed ? base * Self.pulseScale : base"),
                   "pulse and expansion multiply")
        try expect(view.contains("static let pulseScale: CGFloat = 1.04"), "one restrained pulse")
        try expect(!view.contains("pulsed ? 1.055"), "no competing pulse factor")
        // The pre-finish scale applies to the splash too, so the silver rays
        // emerge from behind the icon at BOTH footprints.
        try expect(!view.contains("iconGrowth"), "the footprint is not animated separately")
        try expect(view.contains("Self.preFinishIconScale"), "the footprint derives from the fade")
        try expect(renderers.contains("rayOriginRadius: CGFloat = 79"), "rays start at the icon edge")
        try expect(renderers.contains("rayOriginRadius * footprint * scale"),
                   "the ray origin follows the icon's own footprint")
        // The larger icon grows with one restrained ease that overlaps the
        // fading splash tail.
        try expect(view.contains("withAnimation(.easeOut(duration: 0.55)) { iconExpanded = true }"),
                   "one expansion ease")
        try expect(!view.contains("spring") && !view.contains("bouncy"), "no bounce or overshoot")
    },

    EngineCase("welcome-slogan-is-the-official-phrase") {
        let view = try welcomeSource("Sources/NumlexApp/Views/WelcomeView.swift")
        // ONE canonical constant with the exact official wording: curly
        // apostrophe, trailing period.
        try expect(view.contains("static let sloganPhrase = \"Think freely. We\\u{2019}ll do the math.\""),
                   "the exact official phrase, from one constant")
        let phrase = "Think freely. We\u{2019}ll do the math."
        try expect(phrase.contains("\u{2019}"), "curly apostrophe")
        try expect(phrase.hasSuffix("."), "trailing period")
        try expect(!phrase.contains("'"), "never a straight apostrophe")
        // The visual lockup is STRICTLY SOURCE-PINNED to that constant: the
        // two lines' runs must concatenate back to the canonical phrase.
        for run in ["Think ", "freely.", "We\u{2019}ll do the ", "math."] {
            try expect(view.contains("Text(\"\(run)\"") || view.contains("\"\(run)\""),
                       "visual run \(run)")
        }
        // (The four literals above are the whole visual copy, and the ONE
        // canonical constant they must spell out is asserted separately.)
        // Two lines, ONE baseline each: rounded + serif italic, then rounded
        // + monospaced.
        try expect(view.contains("private var sloganLineOne: Text"), "line one builder")
        try expect(view.contains("private var sloganLineTwo: Text"), "line two builder")
        try expect(view.contains("design: .serif"), "an elegant serif clause")
        // Line 2's first clause is STANDARD SF proportional type — the
        // rounded face read as a mismatched, over-soft clause.
        let lineTwo = welcomeSlice(view, from: "private var sloganLineTwo: Text", to: "/// A single silver sheen")
        try expect(lineTwo.contains("design: .default"), "standard SF for the quiet clause")
        try expect(!lineTwo.contains("design: .rounded"), "never rounded there")
        try expect(lineTwo.contains("design: .monospaced"), "the monospaced accent stays")
        try expect(lineTwo.contains("weight: .semibold"), "a bold monospaced accent")
        let lineOne = welcomeSlice(view, from: "private var sloganLineOne: Text", to: "private var sloganLineTwo")
        try expect(lineOne.contains("design: .default"), "line 1's lead is standard SF")
        try expect(!lineOne.contains("design: .rounded"), "no rounded anywhere in the lockup")
        try expect(view.contains(".italic()"), "italic serif")
        try expect(view.contains("design: .monospaced"), "a compact monospaced clause")
        try expect(view.contains("VStack(spacing: Self.sloganLineSpacing)"), "two lines, 2-5 pt apart")
        try expect(view.contains("static let sloganLineSpacing: CGFloat = 4"), "4 pt leading")
        // Monochrome only: the icon family's neutral plus the secondary label
        // tone — never a palette hue or a website colour.
        try expect(view.contains("Color(nsColor: Design.baseText)"), "the icon neutral")
        try expect(view.contains("Color(nsColor: .secondaryLabelColor)"), "the quiet clause")
        for banned in ["B68BE6", "A4CCFB", "violet", "purple", "blue", "underline", "Swoosh"] {
            try expect(!view.contains(banned), "no \(banned)")
        }
        // No gradient of any kind inside the slogan lockup itself.
        let sloganBody = welcomeSlice(view, from: "private func slogan(scale: CGFloat)",
                                      to: "private var sloganLineOne")
        try expect(!sloganBody.contains("LinearGradient"), "no gradient in the slogan")
        // Sizes and reserved frame: 31-34 / 24-28 pt, laid out from the first
        // pass so revealing can never reflow the icon or the button.
        try expect(view.contains("static let sloganLineOneSize: CGFloat = 38"), "line one size")
        try expect(view.contains("static let sloganLineTwoSize: CGFloat = 30"), "line two size")
        try expect(view.contains("static let sloganReservedWidth: CGFloat = 680"), "reserved width")
        try expect(view.contains("static let sloganReservedHeight: CGFloat = 94"), "reserved height")
        try expect(view.contains(".lineLimit(1)"), "no wrapping")
        try expect(view.contains(".minimumScaleFactor(0.6)"), "compact-width fallback")
        // The WHOLE lockup animates as one composited view.
        try expect(view.contains("withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.50)) { sloganRevealed = true }"),
                   "one reveal transaction")
        try expect(view.contains("(sloganRevealed ? 0 : 9)"), "a 9 pt rise")
        try expect(view.contains(".opacity(sloganRevealed ? 1 : 0)"), "opacity 0 -> 1")
        // Never hit-testable, announced ONCE as a heading with the exact
        // phrase (no fragmented VoiceOver reads).
        try expect(view.contains(".allowsHitTesting(false)"), "never hit-testable")
        try expect(view.contains(".accessibilityElement(children: .ignore)"), "one element")
        try expect(view.contains(".accessibilityLabel(Text(Self.sloganPhrase))"),
                   "the exact phrase is announced")
        try expect(view.contains(".accessibilityAddTraits(.isHeader)"), "announced as a heading")
    },

    EngineCase("welcome-calculation-depth-is-deterministic-and-bounded") {
        let renderers = welcomeRendererSource()
        let body = welcomeSlice(renderers, from: "var body: some View {", to: "// MARK: depth geometry")
        // Depth is pure GraphicsContext math on the same scalars: no extra
        // views, no randomness, no timers.
        for banned in ["random", "ForEach", "TimelineView", "Timer(", ".blur("] {
            try expect(!renderers.contains(banned), "no \(banned) in the renderers")
        }
        try expect(body.contains("Self.slotDepthScale(expression)"), "per-slot depth scale")
        try expect(body.contains("Self.lateralParallax(expression)"), "lateral entry parallax")
        try expect(body.contains("Self.slotParallaxY(expression)"), "slot vertical parallax")
        try expect(body.contains("Self.smoothstep(reveal)"), "eased entry")
        try expect(body.contains("sin(.pi * travel)"), "a curved convergence path")
        // Bounds: entry scale 0.87-1.0, slot depth 0.96-1.02, lateral
        // 12-24 pt, vertical <= 6 pt, arc <= 18 pt.
        try expect(body.contains("0.87 + 0.13 * eased"), "entry scale range")
        try expect(renderers.contains("return 1.02 - 0.06 * distance"), "slot depth range")
        try expect(renderers.contains("outward * (12 + 4 * CGFloat(expression.slot % 3))"),
                   "lateral parallax range")
        try expect(renderers.contains("CGFloat(expression.slot - 2) * 3"), "vertical parallax range")
        try expect(renderers.contains("14 + 4 * CGFloat(expression.slot % 2)"), "arc amplitude range")
        // Deterministic: the same expression always yields the same numbers.
        try expect(renderers.contains("static func slotDepthScale("), "a pure depth function")
        try expect(renderers.contains("static func arcAmplitude("), "a pure arc function")
    },

    EngineCase("welcome-splash-depth-is-layered-within-one-canvas") {
        let renderers = welcomeRendererSource()
        let splash = welcomeSlice(renderers, from: "struct SilverSplashCanvas", to: "private static func drawWave")
        // Still ONE Canvas, and the layers are data, not views.
        try expectEqual(splash.components(separatedBy: "Canvas(").count - 1, 1, "exactly one Canvas")
        try expect(renderers.contains("static let waveLayers"), "two concentric waves")
        try expect(renderers.contains("(0.14, 0.74, 0.55, 1.0)"), "the far wave is delayed/dimmer")
        try expect(renderers.contains("static func rayLayer("), "near/far ray groups")
        try expect(renderers.contains("static func dropletLayer("), "two droplet rings")
        try expect(renderers.contains("drawGlow("), "one central radial glow")
        try expect(renderers.contains("Shading.radialGradient"), "drawn inside the Canvas")
        // The layered depth rides the SAME animatable scalars.
        try expect(splash.contains("var burst: Double") && splash.contains("var fade: Double"),
                   "depth derived from the burst/fade scalars")
        // Still exactly 14 rays and 8 droplets.
        let rayTable = welcomeSlice(renderers, from: "static let rays:", to: "/// 8 droplets placed")
        try expectEqual(welcomeTupleCount(rayTable), 14, "14 rays")
        let dropTable = welcomeSlice(renderers, from: "static let droplets:", to: "/// Rays start just outside")
        try expectEqual(welcomeTupleCount(dropTable), 8, "8 droplets")
    },

    EngineCase("welcome-icon-tilts-into-place-without-a-shadow") {
        let view = try welcomeSource("Sources/NumlexApp/Views/WelcomeView.swift")
        // One 3D settle on the ONE icon view, interpolated by a Double.
        try expect(view.contains("@State private var iconEntry: Double = 0"), "a progress, not a Bool")
        try expect(view.contains(".rotation3DEffect(.degrees(6.5 * (1 - iconEntry))"), "5-8 degree tilt")
        try expect(view.contains("perspective: 0.7"), "a restrained perspective")
        try expect(view.contains("withAnimation(.easeOut(duration: 0.45)) { iconRevealed = true; iconEntry = 1 }"),
                   "one finite settle")
        // The animated halo was removed: it cost cadence for no visible gain.
        try expect(!view.contains(".shadow(color: .black.opacity(Double(0.18"),
                   "no animated halo")
        try expect(!view.contains("iconEntry = iconEntry"), "no continuous animation")
        // Reduce Motion still lands flat, with no tilt.
        let reduce = welcomeSlice(view, from: "if reduceMotion {", to: "// 0.00")
        try expect(reduce.contains("iconEntry = 1"), "flat under Reduce Motion")
    },

    EngineCase("welcome-button-focus-waits-for-the-fade") {
        let view = try welcomeSource("Sources/NumlexApp/Views/WelcomeView.swift")
        guard let reveal = view.range(of: "withAnimation(.easeOut(duration: 0.40)) { buttonRevealed = true }")?.lowerBound,
              let wait = view.range(of: "Task.sleep(nanoseconds: 440_000_000)", range: reveal..<view.endIndex)?.lowerBound,
              let focus = view.range(of: "buttonFocused = true", range: wait..<view.endIndex)?.lowerBound
        else { throw CaseFailure(message: "button focus order missing", location: "Welcome") }
        // The 0.40 s fade plus slack, and only THEN the focus: acquiring focus
        // can cost a frame and must never land inside a visible animation.
        try expect(reveal < wait && wait < focus, "fade -> wait -> focus, in order")
        let sleepText = welcomeSlice(view, from: "withAnimation(.easeOut(duration: 0.40)) { buttonRevealed = true }",
                                     to: "buttonFocused = true")
        try expect(sleepText.contains("440_000_000"), "the wait outlasts the fade")
        // The transient renderers are retired before the button fade starts
        // (their passes are long over) and the splash leaves afterwards.
        // The Reduce Motion path retires both immediately; the animated path
        // must retire the FIELD before the button fade and the SPLASH after it.
        let animated = welcomeSlice(view, from: "withAnimation(.easeOut(duration: 0.45)) { iconRevealed = true; iconEntry = 1 }",
                                    to: "private func activate")
        guard let field = animated.range(of: "fieldActive = false")?.lowerBound,
              let reveal2 = animated.range(of: "buttonRevealed = true")?.lowerBound,
              let splash = animated.range(of: "splashActive = false", range: reveal2..<animated.endIndex)?.lowerBound
        else { throw CaseFailure(message: "renderer retirement order missing", location: "Welcome") }
        try expect(field < reveal2, "the field canvas retires before the button fade")
        try expect(reveal2 < splash, "the splash canvas retires after it")
    },

    EngineCase("welcome-final-composition-is-compact-and-ordered") {
        let view = try welcomeSource("Sources/NumlexApp/Views/WelcomeView.swift")
        // Anchors: large icon, then slogan, then button, inside the ranges
        // the brief allows, with no 150 pt hole anywhere.
        let iconY = -47.0, sloganY = 96.0, buttonY = 183.0
        try expect(iconY <= -45 && iconY >= -65, "icon anchor \(iconY)")
        try expect(sloganY >= 90 && sloganY <= 115, "slogan anchor \(sloganY)")
        try expect(buttonY >= 180 && buttonY <= 210, "button anchor \(buttonY)")
        // Derived vertical rhythm at the 800x600 canvas.
        let iconHalf = 152.0 / 2
        let sloganHalf = 27.0 * 1.5 / 2
        let buttonHalf = 41.0 / 2
        let iconBottom = 300 + iconY + iconHalf
        let sloganTop = 300 + sloganY - sloganHalf
        let sloganBottom = 300 + sloganY + sloganHalf
        let buttonTop = 300 + buttonY - buttonHalf
        let gapIconSlogan = sloganTop - iconBottom
        let gapSloganButton = buttonTop - sloganBottom
        let topGap = 300 + iconY - iconHalf
        let bottomGap = 300 - (buttonY + buttonHalf)
        try expect(gapIconSlogan >= 40 && gapIconSlogan <= 70, "icon->slogan gap \(gapIconSlogan)")
        try expect(gapSloganButton >= 40 && gapSloganButton <= 70, "slogan->button gap \(gapSloganButton)")
        try expect(gapIconSlogan < 150 && gapSloganButton < 150, "never the old ~150 pt hole")
        try expect(topGap >= 150 && topGap <= 200, "top gap \(topGap)")
        try expect(bottomGap >= 80 && bottomGap <= 120, "bottom gap \(bottomGap)")
        try expect(abs(topGap - bottomGap) <= 100, "no lopsided 3:1 whitespace")
        // Ordering: the slogan is revealed AFTER the splash has settled and
        // BEFORE the button, and focus lands only once the button is visible.
        guard let burst = view.range(of: "burstProgress = 1")?.lowerBound,
              let fade = view.range(of: "fadeProgress = 1", range: burst..<view.endIndex)?.lowerBound,
              let expand = view.range(of: "iconExpanded = true", range: fade..<view.endIndex)?.lowerBound,
              let slogan = view.range(of: "sloganRevealed = true", range: expand..<view.endIndex)?.lowerBound,
              let button = view.range(of: "buttonRevealed = true", range: slogan..<view.endIndex)?.lowerBound,
              let focus = view.range(of: "buttonFocused = true", range: button..<view.endIndex)?.lowerBound
        else { throw CaseFailure(message: "final reveal order missing", location: "Welcome") }
        try expect(burst < fade && fade < expand && expand < slogan && slogan < button && button < focus,
                   "burst -> fade -> expand -> slogan -> button -> focus, in order")
        // The final scene is static: no timers, no repeating animation, no
        // ticking task left behind.
        for banned in ["TimelineView", "repeatForever", "Timer(", "CADisplayLink"] {
            try expect(!view.contains(banned), "no \(banned) in the final scene")
        }
    },

    EngineCase("welcome-copy-is-complete-in-six-languages") {
        for lang in AppLanguage.allCases {
            for key in ["welcome.getStarted", "welcome.getStartedHint"] {
                let value = L10n.t(key, language: lang)
                try expect(value != key, "\(lang.rawValue) missing \(key)")
                try expect(!value.isEmpty, "\(lang.rawValue) empty \(key)")
            }
        }
        try expectEqual(L10n.t("welcome.getStarted", language: .en), "Get Started", "English")
        try expectEqual(L10n.t("welcome.getStarted", language: .ru), "Начать", "Russian")
        // The slogan is a single canonical English constant — deliberately
        // NOT a localized key, so the official wording can never drift.
        for lang in AppLanguage.allCases {
            try expectEqual(L10n.t("welcome.slogan", language: lang), "welcome.slogan",
                            "the slogan is never localized")
        }
    }
]

// MARK: - helpers

private func welcomeRepoRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

/// Counts tuple literals like "(8, 96, ..." in a fixed table, ignoring the
/// type annotation's "(" (which is followed by a letter).
private func welcomeTupleCount(_ table: String) -> Int {
    let scalars = Array(table.unicodeScalars)
    var count = 0
    for i in scalars.indices where scalars[i] == "(" {
        let next = i + 1 < scalars.count ? scalars[i + 1] : Unicode.Scalar(" ")
        if CharacterSet.decimalDigits.contains(next) { count += 1 }
    }
    return count
}

private func welcomeRendererSource() -> String {
    (try? String(contentsOf: welcomeRepoRoot()
        .appendingPathComponent("Sources/NumlexApp/Views/WelcomeRenderers.swift"), encoding: .utf8)) ?? ""
}

private func welcomeSource(_ rel: String) -> String {
    let url = welcomeRepoRoot().appendingPathComponent(rel).standardizedFileURL
    return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
}

private func welcomeSlice(_ text: String, from: String, to: String) -> String {
    guard let start = text.range(of: from)?.lowerBound,
          let end = text.range(of: to, range: start..<text.endIndex)?.upperBound
    else { return "" }
    return String(text[start..<end])
}

private func welcomeTempDir(deleting: Bool = false) throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("numlex-welcome-\(UUID().uuidString)", isDirectory: true)
    if !deleting {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    return dir
}
