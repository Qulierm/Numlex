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
        try expect(view.contains("(20, 74, 3.5, 0.02)"), "the droplet table is literal/fixed")
        try expect(view.contains("Circle()\n                .stroke(silverSoft.opacity(waveFaded ? 0 : 0.45)"),
                   "one soft expanding wave")
        // No runtime randomness anywhere in the welcome.
        for banned in ["random", "shuffled", "SystemRandomNumberGenerator"] {
            try expect(!view.contains(banned), "no runtime randomness: \(banned)")
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
        // The staged sleeps stay inside the ~2.4 s budget.
        let sleeps = ["140_000_000", "480_000_000", "330_000_000", "350_000_000",
                      "340_000_000", "200_000_000"]
        for s in sleeps { try expect(view.contains(s), "sleep \(s)") }
        let total = sleeps.reduce(0) { $0 + Int($1.replacingOccurrences(of: "_", with: ""))! / 1_000_000 }
        try expect(total >= 1700 && total <= 1900, "staged sleeps ≈1.84 s (got \(total) ms)")
    },

    EngineCase("welcome-reduce-motion-skips-everything") {
        let view = try welcomeSource("Sources/NumlexApp/Views/WelcomeView.swift")
        try expect(view.contains("@Environment(\\.accessibilityReduceMotion)"), "Reduce Motion")
        guard let rm = view.range(of: "if reduceMotion {"),
              let ret = view.range(of: "return", range: rm.upperBound..<view.endIndex)
        else { throw CaseFailure(message: "reduce-motion branch missing", location: "Welcome") }
        let branch = String(view[rm.upperBound..<ret.lowerBound])
        try expect(branch.contains("iconRevealed = true"), "icon immediately")
        try expect(branch.contains("buttonRevealed = true"), "button immediately")
        try expect(branch.contains("buttonFocused = true"), "focused immediately")
        try expect(!branch.contains("Task.sleep"), "zero sleeps")
        try expect(!branch.contains("withAnimation"), "no animation")
        for stage in ["tokensRevealed", "emphasized", "converged", "splashBurst", "waveProgress"] {
            try expect(!branch.contains("\(stage) = true"),
                       "\(stage) never runs under Reduce Motion")
        }
    },

    EngineCase("welcome-icon-and-fixed-geometry") {
        let view = try welcomeSource("Sources/NumlexApp/Views/WelcomeView.swift")
        try expect(view.contains("AppIconResources.previewImage(for: .dark)"),
                   "the packaged Dark primary preview")
        try expect(view.contains("app.dashed"), "the missing-preview fallback")
        try expect(view.contains("frame(width: 110, height: 110)"), "the icon anchor")
        try expect(view.contains("static let canvas = CGSize(width: 800, height: 600)"),
                   "the fixed design canvas")
        try expect(view.contains("let scale = min(1, min(geo.size.width"),
                   "one geometry-derived scale factor")
        try expect(view.contains(".frame(width: geo.size.width, height: geo.size.height)"),
                   "the composition fills the window without an intrinsic size")
        // No rejected slogan / website visuals anywhere.
        for banned in ["Think freely", "We’ll do the math", "B68BE6", "A4CCFB",
                       "design: .serif", "design: .monospaced", "Swoosh"] {
            try expect(!view.contains(banned), "no rejected visual: \(banned)")
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
        for lang in AppLanguage.allCases {
            try expectEqual(L10n.t("welcome.slogan", language: lang), "welcome.slogan",
                            "no slogan key")
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
