import Foundation
import NumlexCore

/// r97 (revised): the first-launch "calculation bloom" — the pure
/// first-launch policy matrix plus the source contracts of the native
/// composition, the one-shot choreography and the launch integration.
/// The app target is not importable from the test kit, so the view/launch
/// invariants are pinned at the source (like the other app-layer cases).
public let welcomeCases: [EngineCase] = [

    // MARK: - First-launch policy (pure)

    EngineCase("welcome-marker-name-is-versioned") {
        try expectEqual(FirstLaunch.markerFileName, "welcome-v1",
                        "the completion marker is versioned")
        try expect(!FirstLaunch.markerFileName.contains("store"), "not the store")
        try expectEqual(FirstLaunch.artifactFileNames,
                        ["store.json", "rates.json", "weather.json", "locations.json"],
                        "exactly the known data-directory artifacts")
    },

    EngineCase("welcome-empty-directory-shows-welcome") {
        let dir = try welcomeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try expect(FirstLaunch.shouldShowWelcome(in: dir), "a new install")
        try expect(!FirstLaunch.isCompleted(in: dir), "no marker yet")
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
        // Presence — not decodability — decides.
        try Data([0x00, 0xFF, 0x13, 0x37]).write(
            to: dir.appendingPathComponent("store.json"))
        try expect(!FirstLaunch.shouldShowWelcome(in: dir),
                   "a corrupt store still suppresses onboarding")
        try expect(Persistence.load(from: dir) == nil,
                   "and it is genuinely unreadable")
    },

    EngineCase("welcome-existing-install-records-marker-without-touching-store") {
        // The ONE allowed migration effect: an existing install gets the
        // completion marker best-effort, so deleting a cache later never
        // turns that user into a "new" one. Store bytes stay identical.
        let dir = try welcomeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        var payload = StorePayload(sheets: [], selectedIndex: 0,
                                   settings: AppSettings(), version: 2)
        payload.settings.appearance = .light
        payload.settings.appIcon = .light
        Persistence.save(payload, to: dir)
        let before = try Data(contentsOf: Persistence.storeURL(in: dir))
        try expect(!FirstLaunch.evaluateAtLaunch(in: dir),
                   "an existing install never sees the welcome")
        try expect(FirstLaunch.isCompleted(in: dir),
                   "…and the completion marker was recorded")
        try expectEqual(try Data(contentsOf: Persistence.storeURL(in: dir)), before,
                        "the store bytes are byte-identical")
        guard let reloaded = Persistence.load(from: dir) else {
            throw CaseFailure(message: "store still decodes", location: "Welcome")
        }
        try expectEqual(reloaded.settings.appearance, .light, "explicit appearance kept")
        try expectEqual(reloaded.settings.appIcon, .light, "explicit icon kept")
        try expectEqual(StorePayload.currentVersion, 2, "schema version untouched")
        // Deleting the cache later must not resurrect onboarding.
        try FileManager.default.removeItem(at: dir.appendingPathComponent("store.json"))
        try expect(!FirstLaunch.shouldShowWelcome(in: dir),
                   "the marker keeps the install 'known' after a cache delete")
    },

    EngineCase("welcome-cache-only-directory-suppresses") {
        let dir = try welcomeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("{}".utf8).write(to: dir.appendingPathComponent("rates.json"))
        try expect(!FirstLaunch.evaluateAtLaunch(in: dir),
                   "a previous user with no saved edit is still an existing user")
        try expect(FirstLaunch.isCompleted(in: dir), "marker recorded")
        try expect(!FileManager.default.isReadableFile(
                    atPath: Persistence.storeURL(in: dir).path),
                   "no store was created")
    },

    EngineCase("welcome-marker-completes-and-is-idempotent") {
        let dir = try welcomeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try expect(FirstLaunch.evaluateAtLaunch(in: dir), "a fresh install")
        try expect(!FirstLaunch.isCompleted(in: dir),
                   "the launch itself writes nothing")
        try expectEqual(FirstLaunch.markCompleted(in: dir), true, "Get Started writes")
        let marker = dir.appendingPathComponent(FirstLaunch.markerFileName)
        try expectEqual(try String(contentsOf: marker, encoding: .utf8), "1\n",
                        "the marker carries its version payload")
        try expectEqual(FirstLaunch.markCompleted(in: dir), true, "idempotent")
        try expectEqual(try String(contentsOf: marker, encoding: .utf8), "1\n",
                        "the marker content is stable")
        try expect(!FirstLaunch.shouldShowWelcome(in: dir), "no welcome next launch")
    },

    EngineCase("welcome-aborted-launch-keeps-welcome") {
        let dir = try welcomeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = FirstLaunch.evaluateAtLaunch(in: dir)   // decided, nothing pressed
        try expect(!FirstLaunch.isCompleted(in: dir), "no marker was written")
        try expect(FirstLaunch.shouldShowWelcome(in: dir),
                   "the welcome returns on the next launch")
    },

    EngineCase("welcome-decision-works-before-the-directory-exists") {
        let dir = try welcomeTempDir(deleting: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try expect(!FileManager.default.fileExists(atPath: dir.path),
                   "the fixture directory does not exist yet")
        try expect(FirstLaunch.shouldShowWelcome(in: dir),
                   "the pure decision works on a non-existent directory")
        try expect(FirstLaunch.evaluateAtLaunch(in: dir),
                   "and the launch entry point does too")
        try expect(!FirstLaunch.isCompleted(in: dir),
                   "with no artifact present nothing is written")
    },

    // MARK: - Launch integration (source)

    EngineCase("welcome-decision-precedes-model-and-store") {
        let app = try welcomeSource("Sources/NumlexApp/NumlexApp.swift")
        guard let decision = app.range(of: "FirstLaunch.evaluateAtLaunch(in: dataDirectory)"),
              let modelInit = app.range(of: "AppModel()") else {
            throw CaseFailure(message: "decision/model init missing", location: "Welcome")
        }
        try expect(decision.lowerBound < modelInit.lowerBound,
                   "the decision is captured before the model")
        try expect(app.contains("Persistence.dataDirectory(createIfNeeded: false)"),
                   "the decision uses the NON-creating directory lookup")
        try expect(app.contains("WelcomeView(language: model.settings.language"),
                   "the bloom is wired to the launch root")
        try expect(app.contains("onGetStarted: completeWelcome"),
                   "the ONE dismissal path is completeWelcome")
        let complete = welcomeSlice(app, from: "private func completeWelcome()",
                                    to: "\n    }")
        try expect(!complete.contains("newSheet"), "no sheet is created on dismissal")
        try expect(!complete.contains("persist("), "dismissal never persists")
        try expect(app.contains("model.focusSheetID = id"),
                   "the hand-off requests focus for the existing selection")
        try expect(app.contains("FirstLaunch.markCompleted(in: Persistence.dataDirectory())"),
                   "completion records the marker")
    },

    // MARK: - Composition (source)

    EngineCase("welcome-slogan-and-website-visuals-are-gone") {
        let view = try welcomeSource("Sources/NumlexApp/Views/WelcomeView.swift")
        for banned in ["Think freely", "We’ll do the math", "freely.", "math.",
                       "B68BE6", "A4CCFB", "182, 139, 230", "164, 204, 251",
                       "11, 11, 14", "design: .serif", "design: .monospaced"] {
            try expect(!view.contains(banned), "no rejected slogan/website visual: \(banned)")
        }
        try expect(!view.contains("Swoosh"), "no website underline shape")
        let docs = try welcomeSource("README.md")
        try expect(!docs.contains("Think freely"), "no slogan in the README")
        let settings = try welcomeSource("docs/SETTINGS_AND_APPEARANCE.md")
        try expect(!settings.contains("Think freely"), "no slogan in the docs")
    },

    EngineCase("welcome-calculation-expressions-are-exact") {
        let view = try welcomeSource("Sources/NumlexApp/Views/WelcomeView.swift")
        // The four expressions, token by token (arithmetic must be right).
        for fragment in [
            ".number(\"128\"), .op(\" × \"), .number(\"4\")", ".number(\"512\")",
            ".variable(\"price\"), .op(\" = \"), .number(\"24\")",
            ".number(\"3.5\"), .op(\" \"), .unit(\"km\"), .op(\" → \")",
            ".number(\"3500\")", ".unit(\"m\")",
            ".money(\"$\"), .number(\"42\"), .op(\" + \")", ".number(\"18\")",
            ".op(\" = \")", ".number(\"60\")",
        ] {
            try expect(view.contains(fragment), "expression fragment \(fragment)")
        }
        // Anchors: one expression per corner.
        for anchor in [".topLeft", ".topRight", ".bottomLeft", ".bottomRight"] {
            try expect(view.contains("anchor: \(anchor)"), "expression at \(anchor)")
        }
        try expectEqual(128 * 4, 512, "A is correct arithmetic")
        try expectEqual(42 + 18, 60, "D is correct arithmetic")
        try expectEqual(3.5 * 1000, 3500, "C is a correct km→m conversion")
        // No opaque cards or glass in the field.
        try expect(!view.contains("SettingsCardBackground"), "no card surface")
        try expect(!view.contains(".glassEffect("), "no glass rectangles")
        try expect(!view.contains("RoundedRectangle(cornerRadius: 12"), "no expression cards")
    },

    EngineCase("welcome-colors-come-from-the-editor-palette") {
        let view = try welcomeSource("Sources/NumlexApp/Views/WelcomeView.swift")
        for token in ["Design.numberColor", "Design.variableColor",
                      "Design.conversionColor", "Design.moneyMarkerColor",
                      "Design.baseText", "Design.editorBackground"] {
            try expect(view.contains(token), "the field uses \(token)")
        }
        // Colour comes from the app tokens, never copied hexes.
        try expect(view.contains("Color(nsColor: Design."), "tokens resolve to SwiftUI Color")
        try expect(!view.contains("Color(srgb255"), "no hardcoded sRGB in the welcome")
        try expect(!view.contains("Color(red:"), "no hardcoded RGB in the welcome")
    },

    EngineCase("welcome-icon-and-fixed-geometry") {
        let view = try welcomeSource("Sources/NumlexApp/Views/WelcomeView.swift")
        try expect(view.contains("AppIconResources.previewImage(for: .dark)"),
                   "the packaged Dark primary preview")
        try expect(view.contains("app.dashed"), "the missing-preview fallback")
        try expect(view.contains("frame(width: 110, height: 110)"),
                   "the icon is the visual anchor (~104–116 pt)")
        try expect(view.contains("let scale = min(1, min(geo.size.width"),
                   "one geometry-derived scale factor")
        try expect(view.contains("canvas = CGSize(width: 800, height: 600)"),
                   "the fixed design canvas")
        try expect(!view.contains(".frame(minWidth: 0") , "no collapsing frames")
    },

    EngineCase("welcome-bloom-is-one-shot-within-budget") {
        let view = try welcomeSource("Sources/NumlexApp/Views/WelcomeView.swift")
        // No perpetual animation machinery at all.
        for banned in ["TimelineView", "repeatForever", "phaseAnimator",
                       "Timer(", "repeating"] {
            try expect(!view.contains(banned), "no \(banned)")
        }
        try expect(view.contains(".task { await bloom() }"),
                   "one structured task drives the sequence")
        try expect(view.contains("if Task.isCancelled { return }"),
                   "the task checks cancellation")
        // Stage markers.
        for stage in ["iconRevealed", "tokensRevealed", "emphasized", "converged",
                      "arcProgress", "arcsFaded", "pulsed", "sheenProgress",
                      "buttonRevealed"] {
            try expect(view.contains("$\(stage)") || view.contains("\(stage) ="),
                       "stage \(stage) exists")
        }
        // Geometry-neutral properties only.
        for prop in ["opacity(", "offset(", "scaleEffect(", ".trim(", "rotationEffect("] {
            try expect(view.contains(prop), "uses \(prop)")
        }
        // The scheduled delays sum to the ~1.8–2.1 s budget (1.65 s of
        // sleeps, then the button fade completes it).
        let sleeps = ["180_000_000", "570_000_000", "250_000_000", "100_000_000",
                      "150_000_000", "150_000_000", "100_000_000"]
        for s in sleeps { try expect(view.contains(s), "sleep \(s) present") }
        let total = sleeps.reduce(0) { $0 + Int($1.replacingOccurrences(of: "_", with: ""))! / 1_000_000 }
        try expect(total >= 1500 && total <= 1700,
                   "the staged sleeps total ~1.65 s (got \(total) ms)")
        try expect(view.contains("duration: 0.4"), "the button fade completes the budget")
    },

    EngineCase("welcome-reduce-motion-is-immediate-and-clean") {
        let view = try welcomeSource("Sources/NumlexApp/Views/WelcomeView.swift")
        try expect(view.contains("@Environment(\\.accessibilityReduceMotion)"),
                   "Reduce Motion is observed")
        guard let rm = view.range(of: "if reduceMotion {"),
              let ret = view.range(of: "return", range: rm.upperBound..<view.endIndex)
        else { throw CaseFailure(message: "reduce-motion branch missing", location: "Welcome") }
        let branch = String(view[rm.upperBound..<ret.lowerBound])
        try expect(branch.contains("iconRevealed = true"), "icon shown immediately")
        try expect(branch.contains("buttonRevealed = true"), "button shown immediately")
        try expect(branch.contains("buttonFocused = true"), "button focused immediately")
        try expect(!branch.contains("Task.sleep"), "zero sleeps under Reduce Motion")
        try expect(!branch.contains("withAnimation"), "no animation under Reduce Motion")
        // The decorative field never appears as static clutter: the stages
        // that reveal it stay false in that branch.
        for stage in ["tokensRevealed", "emphasized", "converged"] {
            try expect(!branch.contains("\(stage) = true"),
                       "\(stage) stays hidden under Reduce Motion")
        }
    },

    EngineCase("welcome-button-and-accessibility") {
        let view = try welcomeSource("Sources/NumlexApp/Views/WelcomeView.swift")
        try expect(view.contains("welcome.getStarted"), "the localized button key")
        try expect(view.contains("welcome.getStartedHint"), "a localized hint")
        try expect(view.contains(".buttonStyle(.borderedProminent)"), "native prominent")
        try expect(view.contains(".controlSize(.large)"), "large control")
        try expect(view.contains("frame(minWidth: 190)"), "compact width")
        try expect(view.contains(".keyboardShortcut(.defaultAction)"),
                   "Return/Space activate it")
        try expect(view.contains(".allowsHitTesting(buttonRevealed && !activating)"),
                   "a hidden button cannot be clicked")
        try expect(view.contains(".accessibilityHidden(!buttonRevealed)"),
                   "a hidden button is hidden from VoiceOver")
        try expect(view.contains("guard !activating else { return }"), "double guard")
        // The icon identifies Numlex; the decorative field and arcs are hidden.
        try expect(view.contains(".accessibilityLabel(Text(\"Numlex\"))"),
                   "the icon names the app")
        try expect(view.contains("accessibilityHidden(true)"),
                   "the decorative pieces are hidden")
        let field = welcomeSlice(view, from: "private func calculationField(scale: CGFloat)",
                                 to: "private func expressionRow")
        try expect(field.contains(".accessibilityHidden(true)"),
                   "the calculation field is one hidden decorative element")
    },

    EngineCase("welcome-copy-is-complete-in-six-languages") {
        for lang in AppLanguage.allCases {
            for key in ["welcome.getStarted", "welcome.getStartedHint"] {
                let value = L10n.t(key, language: lang)
                try expect(value != key, "\(lang.rawValue) missing \(key)")
                try expect(!value.isEmpty, "\(lang.rawValue) empty \(key)")
            }
        }
        try expectEqual(L10n.t("welcome.getStarted", language: .en), "Get Started",
                        "English label")
        try expectEqual(L10n.t("welcome.getStarted", language: .ru), "Начать",
                        "natural Russian label")
        // No slogan key exists to translate.
        for lang in AppLanguage.allCases {
            try expectEqual(L10n.t("welcome.slogan", language: lang), "welcome.slogan",
                            "no slogan localization key")
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
