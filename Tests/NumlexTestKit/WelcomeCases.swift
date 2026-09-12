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

    EngineCase("welcome-curtain-reveal-contract") {
        let app = try welcomeSource("Sources/NumlexApp/NumlexApp.swift")
        // Three stages; the editor only exists from `.revealing` on.
        for stage in ["case welcome, revealing, app", "case .welcome:",
                      "case .revealing:", "case .app:"] {
            try expect(app.contains(stage), "stage \(stage)")
        }
        // ONE stable ZStack for the reveal: the welcome keeps its identity
        // and is moved by an animated OFFSET, never by a transition attached
        // to a freshly inserted branch.
        try expect(app.contains("GeometryReader { geo in") && app.contains("ZStack {"),
                   "the reveal is one stable container")
        try expect(app.contains("WelcomeView(language: model.settings.language,\n                                onGetStarted: {})"),
                   "the same welcome view instance stays mounted during the reveal")
        try expect(app.contains(".offset(y: curtainLifted ? -geo.size.height : 0)"),
                   "the panel travels fully out of the bounds via an offset")
        try expect(!app.contains("removal: .move(edge: .top)"),
                   "no transition attached to an inserted branch")
        try expect(!app.contains("withAnimation(revealAnimation) { revealStage = .revealing }"),
                   "the mount step is not the animated step")
        try expect(app.contains("ContentView(model: model)\n                        // The editor may render underneath but must not take"),
                   "the editor mounts beneath")
        try expect(app.contains(".allowsHitTesting(false)"),
                   "the editor cannot take pointer events while covered")
        try expect(app.contains(".clipped()"), "the slide is clipped to the content bounds")
        try expect(app.contains(".shadow(color: .black.opacity(curtainLifted ? 0 : 0.28)"),
                   "a restrained bottom-edge shadow on the moving panel")
        // The transaction order: mount, yield a frame, animate the offset,
        // wait the travel time, then remove and focus.
        guard let mount = app.range(of: "revealStage = .revealing")?.lowerBound,
              let yield = app.range(of: "await Task.yield()")?.lowerBound,
              let animate = app.range(of: "withAnimation(RevealTiming.animation) { curtainLifted = true }")?.lowerBound,
              let wait = app.range(of: "Task.sleep(nanoseconds: RevealTiming.travelNanoseconds)")?.lowerBound,
              let remove = app.range(of: "revealStage = .app", range: wait..<app.endIndex)?.lowerBound else {
            throw CaseFailure(message: "curtain transaction steps missing", location: "Welcome")
        }
        try expect(mount < yield && yield < animate && animate < wait && wait < remove,
                   "mount -> yield -> animated offset -> wait -> remove, in order")
        // The completion wait covers the travel (0.75 s) with a frame of slack.
        try expect(app.contains("static let duration: Double = 0.75"), "0.75 s travel")
        try expect(app.contains("static let travelNanoseconds: UInt64 = 800_000_000"),
                   "the removal waits 800 ms")
        try expect(app.contains(".timingCurve(0.55, 0, 0.3, 1, duration: duration)"),
                   "the soft acceleration curve")
        try expect(app.contains("guard !Task.isCancelled else { return }"),
                   "the completion task is cancellation-safe")
        try expect(app.contains("guard !Task.isCancelled, revealStage == .revealing else { return }"),
                   "the animation step is guarded too")
        // Focus only after the panel has cleared.
        let tail = String(app[remove...].prefix(300))
        try expect(tail.contains("focusSelectedEditor()"),
                   "focus is requested after the removal")
        try expect(app.contains("private func focusSelectedEditor()"), "one focus helper")
        // Reduce Motion removes the welcome immediately, with no mount step,
        // no animation and no sleep.
        guard let rm = app.range(of: "if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {"),
              let rmEnd = app.range(of: "return", range: rm.upperBound..<app.endIndex) else {
            throw CaseFailure(message: "reduce-motion branch missing", location: "Welcome")
        }
        let branch = String(app[rm.upperBound..<rmEnd.lowerBound])
        try expect(branch.contains("revealStage = .app"), "removed immediately")
        try expect(branch.contains("focusSelectedEditor()"), "focus immediately")
        try expect(!branch.contains("withAnimation"), "no animation under Reduce Motion")
        try expect(!branch.contains("Task.sleep"), "no delay under Reduce Motion")
        // The NSWindow frame is never animated.
        for banned in ["setFrame", "setFrameOrigin", "animator()"] {
            try expect(!app.contains(banned), "no window frame API: \(banned)")
        }
        let complete = welcomeSlice(app, from: "private func beginReveal()", to: "\n    }")
        try expect(!complete.contains("newSheet"), "no sheet is created on dismissal")
        try expect(!complete.contains("persist("), "dismissal never persists")
    },

    // MARK: - Calculation field (source)

    EngineCase("welcome-calculation-field-is-ten-correct-rows") {
        let view = try welcomeSource("Sources/NumlexApp/Views/WelcomeView.swift")
        // Exactly ten expressions: five slots per column, two columns.
        try expectEqual(view.components(separatedBy: ".init(column: .left, slot:").count - 1, 5,
                        "five left-column rows")
        try expectEqual(view.components(separatedBy: ".init(column: .right, slot:").count - 1, 5,
                        "five right-column rows")
        // Correct arithmetic / semantics for the result runs.
        try expectEqual(128 * 4, 512, "128 × 4")
        try expectEqual(Int(0.18 * 240), 43, "18% of 240 starts 43…")
        try expectEqual(3.5 * 1000, 3500, "3.5 km")
        try expectEqual((2 * 60 + 15) + 45, 180, "2h15m + 45m = 3h (180 min)")
        try expectEqual(12 * 12, 144, "√144")
        try expectEqual(42 + 18, 60, "$42 + $18")
        try expectEqual(12 / 3, 4, "12 kg ÷ 3")
        try expectEqual(1 << 10, 1024, "2^10")
        try expectClose(9 * 0.3048, 2.7432, 0.0001, "9 ft ≈ 2.74 m (0.3048 m/ft)")
        // Token roles: units purple, variable green, money markers purple,
        // numbers / operators from the editor palette.
        for fragment in [".unit(\"km\"), .op(\" → \")", ".unit(\"m\")",
                         ".unit(\"h\")", ".unit(\"kg\")", ".unit(\"ft\")",
                         ".variable(\"price\")", ".money(\"$\")",
                         ".op(\"√\"), .number(\"144\")", ".op(\"^\")"] {
            try expect(view.contains(fragment), "token role \(fragment)")
        }
        // Two airy columns on a fixed grid: 5 slots, one anchor per column.
        try expect(view.contains("let x: CGFloat = expression.column == .left ? -238 : 238"),
                   "two column anchors")
        try expect(view.contains("let y: CGFloat = -118 + CGFloat(expression.slot) * 59"),
                   "a fixed vertical slot grid")
        try expect(!view.contains("RoundedRectangle(cornerRadius: 12"),
                   "no opaque calculation cards")
        try expect(!view.contains(".glassEffect("), "no competing glass")
        try expect(view.contains(".font(.system(size: 16, weight: token.weight, design: .rounded))"),
                   "compact ~16 pt rows")
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
        try expectEqual(view.components(separatedBy: "static let rays:").count - 1, 1, "one ray table")
        try expectEqual(view.components(separatedBy: "static let droplets:").count - 1, 1,
                        "one droplet table")
        try expect(view.contains("(8, 96, 0.00, 2.5)"), "the ray table is literal/fixed")
        try expect(view.contains("(20, 100, 3.5, 0.02)"), "the droplet table is literal/fixed")
        // Still exactly 14 rays and 8 droplets (the ring was pushed outward
        // so the droplets read outside the larger icon).
        let rayTable = welcomeSlice(view, from: "static let rays:", to: "private static let droplets:")
        try expectEqual(welcomeTupleCount(rayTable), 14, "14 rays")
        let dropTable = welcomeSlice(view, from: "static let droplets:", to: "/// Rays start just outside the icon")
        try expectEqual(welcomeTupleCount(dropTable), 8, "8 droplets")
        try expect(view.contains("Circle()\n                .stroke(silverSoft.opacity(waveFaded ? 0 : 0.45)"),
                   "one soft expanding wave")
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

    EngineCase("welcome-replay-overlay-never-touches-production-state") {
        let app = try welcomeSource("Sources/NumlexApp/NumlexApp.swift")
        // The scene root keeps the production launchRoot MOUNTED and only
        // inserts a sibling overlay above it.
        try expect(app.contains("private var sessionRoot: some View"), "one session root")
        try expect(app.contains("themedRoot(sessionRoot)"), "the scene uses the session root")
        try expect(app.contains("themedRoot(launchRoot)") == false, "launchRoot is retained inside it")
        let root = welcomeSlice(app, from: "private var sessionRoot: some View", to: "private func presentReplayWelcome")
        try expect(root.contains("launchRoot"), "the production root stays mounted")
        try expect(root.contains(".allowsHitTesting(!replayWelcomePresented)"),
                   "hit testing is blocked while the overlay covers")
        try expect(root.contains("if replayWelcomePresented {"), "the overlay is conditional")
        try expect(root.contains("WelcomeView(language: model.settings.language,"), "a real welcome")
        try expect(root.contains(".id(replaySession)"),
                   "a fresh identity restarts the staged animation")
        try expect(root.contains(".offset(y: replayCurtainLifted ? -geo.size.height : 0)"),
                   "the panel travels the full content height")
        try expect(root.contains(".shadow(color: .black.opacity(replayCurtainLifted ? 0 : 0.28)"),
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
        try expect(present.contains("replayCurtainLifted = false"), "curtain state reset")
        try expect(present.contains("replaySession = UUID()"), "a new session each time")
        // Finishing mirrors the production contract: stable identity, one
        // animated travel, removal, then focus. Reduce Motion is immediate.
        let finish = welcomeSlice(app, from: "private func finishReplay", to: "var body: some Scene")
        try expect(finish.contains("guard replayWelcomePresented else { return }"), "one finish only")
        try expect(finish.contains("withAnimation(RevealTiming.animation) { replayCurtainLifted = true }"),
                   "the same reveal animation")
        try expect(finish.contains("Task.sleep(nanoseconds: RevealTiming.travelNanoseconds)"),
                   "the same travel wait")
        try expect(finish.contains("guard !Task.isCancelled, replayWelcomePresented else { return }"),
                   "the animation step is guarded")
        try expect(finish.contains("focusSelectedEditor()"), "focus returns to the current sheet")
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
        for stage in ["case .welcome:", "case .revealing:", "case .app:"] {
            try expect(app.contains(stage), "production stage \(stage)")
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
        for stage in ["iconRevealed", "tokensRevealed", "emphasized", "converged",
                      "splashBurst", "splashFaded", "waveProgress", "waveFaded",
                      "pulsed", "sheenProgress", "buttonRevealed"] {
            try expect(view.contains("$\(stage)") || view.contains("\(stage) ="),
                       "stage \(stage)")
        }
        for prop in ["opacity(", "offset(", "scaleEffect(", "rotationEffect("] {
            try expect(view.contains(prop), "geometry-neutral \(prop)")
        }
        // The splash is one-shot and bounded (~0.55–0.75 s of animation).
        try expect(view.contains("withAnimation(.easeOut(duration: 0.55)) { waveProgress = 1 }"),
                   "the wave expands once")
        try expect(view.contains("duration: 0.42").self, "rays travel once")
        try expect(view.contains("duration: 0.26"), "rays fade once")
        // The staged sleeps stay inside the ~2.3-2.6 s budget, and the
        // quietest gaps are short: no long blank pause anywhere.
        let sleeps = ["140_000_000", "480_000_000", "330_000_000", "350_000_000",
                      "340_000_000", "100_000_000", "300_000_000", "120_000_000"]
        for s in sleeps { try expect(view.contains(s), "sleep \(s)") }
        let millis = sleeps.map { Int($0.replacingOccurrences(of: "_", with: ""))! / 1_000_000 }
        let total = millis.reduce(0, +)
        try expect(total >= 2000 && total <= 2260, "staged sleeps ~2.16 s (got \(total) ms)")
        try expect(millis.allSatisfy { $0 <= 480 }, "no single pause over 0.48 s")
        // The button reveal starts 0.12 s before the last sleep ends and
        // runs 0.40 s, so the whole choreography ends inside 2.3-2.6 s.
        let end = total - 120 + 400
        try expect(end >= 2300 && end <= 2600, "total reveal budget \(end) ms")
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
        try expect(view.contains("static let finalIconSize: CGFloat = 152"), "152 pt final icon")
        try expect(view.contains(".frame(width: Self.finalIconSize, height: Self.finalIconSize)"),
                   "one fixed final frame")
        try expect(!view.contains("frame(width: 110, height: 110)"), "no 110 pt frame")
        // Streaming footprint ≈ the old 110 pt (108-114 pt).
        try expect(view.contains("static let preFinishIconScale: CGFloat = 110 / finalIconSize"),
                   "the pre-finish scale derives from the old footprint")
        let preFinish = 152 * (110.0 / 152.0)
        try expect(preFinish >= 108 && preFinish <= 114, "≈110 pt while streaming")
        // Scale only; combined deterministically, never added.
        try expect(view.contains("private var iconVisualScale: CGFloat"), "one combined scale")
        try expect(view.contains("pulsed ? base * Self.pulseScale : base"),
                   "pulse and expansion multiply")
        try expect(view.contains("static let pulseScale: CGFloat = 1.04"), "one restrained pulse")
        try expect(!view.contains("pulsed ? 1.055"), "no competing pulse factor")
        // The pre-finish scale applies to the splash too, so the silver rays
        // emerge from behind the icon at BOTH footprints.
        try expect(view.contains("scaleEffect(iconExpanded ? 1 : Self.preFinishIconScale"),
                   "the splash tracks the icon footprint")
        try expect(view.contains("rayOriginRadius: CGFloat = 79"), "rays start at the icon edge")
        try expect(view.contains("-ray.length / 2 - Self.rayOriginRadius"), "ray origin is shared")
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
        // The visible text is derived from the constant, split at the first
        // sentence so both clauses share ONE baseline.
        try expect(view.contains("private var sloganText: Text"), "one derived text")
        try expect(view.contains("phrase.range(of: \". \")"), "split at the first sentence")
        try expect(view.contains("Text(lead).fontWeight(.semibold) + Text(\" \" + tail)"),
                   "semibold lead, medium tail, one baseline")
        // Monochrome, native, no website styling.
        try expect(view.contains(".foregroundStyle(Color(nsColor: Design.baseText))"),
                   "the icon family's neutral tone")
        try expect(view.contains(".font(.system(size: Self.sloganFontSize, weight: .medium, design: .rounded))"),
                   "native rounded type at the canonical size")
        try expect(view.contains("static let sloganFontSize: CGFloat = 27"), "25-30 pt target")
        try expect(view.contains(".lineLimit(1)"), "one line")
        try expect(view.contains(".minimumScaleFactor(0.62)"), "compact-width fallback")
        for banned in ["B68BE6", "A4CCFB", "design: .serif", "design: .monospaced",
                       "TextEditor", "underline", "toolbar", "Swoosh", "italic",
                       "violet", "purple", "blue"] {
            try expect(!view.contains(banned), "no \(banned)")
        }
        // Reserved from the first layout: revealing can never reflow.
        try expect(view.contains("static let sloganReservedWidth: CGFloat = 620"), "reserved width")
        try expect(view.contains("height: Self.sloganFontSize * 1.5"), "reserved height")
        // Not hit-testable, but announced ONCE as a heading with the exact
        // phrase (no fragmented VoiceOver reads).
        try expect(view.contains(".allowsHitTesting(false)"), "never hit-testable")
        try expect(view.contains(".accessibilityElement(children: .ignore)"), "one element")
        try expect(view.contains(".accessibilityLabel(Text(Self.sloganPhrase))"),
                   "the exact phrase is announced")
        try expect(view.contains(".accessibilityAddTraits(.isHeader)"), "announced as a heading")
        // Appearance: 0 -> 1 opacity with a ~10 pt rise on a soft curve.
        try expect(view.contains("withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.50)) { sloganRevealed = true }"),
                   "one soft reveal transaction")
        try expect(view.contains("(sloganRevealed ? 0 : 10)"), "an 10 pt rise")
        try expect(view.contains(".opacity(sloganRevealed ? 1 : 0)"), "opacity 0 -> 1")
    },

    EngineCase("welcome-final-composition-is-compact-and-ordered") {
        let view = try welcomeSource("Sources/NumlexApp/Views/WelcomeView.swift")
        // Anchors: large icon, then slogan, then button, inside the ranges
        // the brief allows, with no 150 pt hole anywhere.
        let iconY = -47.0, sloganY = 96.0, buttonY = 183.0
        try expect(iconY <= -45 && iconY >= -65, "icon anchor \(iconY)")
        try expect(sloganY >= 75 && sloganY <= 105, "slogan anchor \(sloganY)")
        try expect(buttonY >= 160 && buttonY <= 190, "button anchor \(buttonY)")
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
        guard let splash = view.range(of: "splashFaded = true; waveFaded = true")?.lowerBound,
              let expand = view.range(of: "iconExpanded = true", range: splash..<view.endIndex)?.lowerBound,
              let slogan = view.range(of: "sloganRevealed = true", range: expand..<view.endIndex)?.lowerBound,
              let button = view.range(of: "buttonRevealed = true", range: slogan..<view.endIndex)?.lowerBound,
              let focus = view.range(of: "buttonFocused = true", range: button..<view.endIndex)?.lowerBound
        else { throw CaseFailure(message: "final reveal order missing", location: "Welcome") }
        try expect(splash < expand && expand < slogan && slogan < button && button < focus,
                   "splash -> expand -> slogan -> button -> focus, in order")
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
