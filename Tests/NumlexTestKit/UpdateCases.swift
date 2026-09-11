//
//  UpdateCases.swift
//  NumlexTestKit
//
//  Secure in-app updates (Sparkle 2.9.6): the pure configuration contract,
//  the six-language L10n coverage, and source-level invariants for the
//  integration (no duplicated automatic-check state, no custom updater
//  window, exact Sparkle pin, packaged metadata parity).
//

import Foundation
import NumlexCore

public var updateCases: [EngineCase] {
    updateConfigurationCases + updateLocalizationCases + updateSourceInvariantCases
}

// MARK: - helpers

private func updateRepoFile(_ rel: String) -> String? {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // NumlexTestKit
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repo root
    let url = root.appendingPathComponent(rel).standardizedFileURL
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try? String(contentsOf: url, encoding: .utf8)
}

/// The four Sparkle keys as the packaged app must carry them. A function
/// (not a global) keeps the non-Sendable `[String: Any]` out of global state.
private func updateSourceInfo() -> [String: Any] {
    [

    "CFBundleVersion": "4.8.1",
    "SUFeedURL": "https://numlex.tech/appcast.xml",
    "SUPublicEDKey": "0DwkW0VipX8QYmJ+AcX8xN/lsaweS3WXO68L9Mrc4Vo=",
    "SUVerifyUpdateBeforeExtraction": true,
    "SUEnableSystemProfiling": false,
    ]
}

// MARK: - configuration (pure)

private let updateConfigurationCases: [EngineCase] = [
    EngineCase("updates.config-valid") {
        let c = UpdateConfiguration.from(infoDictionary: updateSourceInfo())
        try expectEqual(c.isUsable, true, "packaged metadata is usable")
        try expectEqual(c.unavailableReason, nil, "no reason")
        try expectEqual(c.hasUsableFeedURL, true, "https feed")
        try expectEqual(c.hasValidPublicKey, true, "32-byte base64 key")
        try expectEqual(c.verifiesBeforeExtraction, true, "verify before extraction")
        try expectEqual(c.systemProfilingEnabled, false, "profiling off")
        try expectEqual(c.feedURL?.absoluteString, "https://numlex.tech/appcast.xml", "feed")
    },
    EngineCase("updates.config-missing-feed-disables") {
        var info = updateSourceInfo()
        info.removeValue(forKey: "SUFeedURL")
        let c = UpdateConfiguration.from(infoDictionary: info)
        try expectEqual(c.isUsable, false, "no feed -> disabled")
        try expectEqual(c.unavailableReason, .missingFeedURL, "typed reason")
    },
    EngineCase("updates.config-http-feed-disables") {
        var info = updateSourceInfo()
        info["SUFeedURL"] = "http://numlex.tech/appcast.xml"
        let c = UpdateConfiguration.from(infoDictionary: info)
        try expectEqual(c.isUsable, false, "http feed -> disabled")
        try expectEqual(c.unavailableReason, .insecureFeedURL, "typed reason")
        try expectEqual(c.hasUsableFeedURL, false, "insecure scheme rejected")
    },
    EngineCase("updates.config-relative-feed-disables") {
        var info = updateSourceInfo()
        info["SUFeedURL"] = "appcast.xml"
        try expectEqual(UpdateConfiguration.from(infoDictionary: info).unavailableReason,
                        .insecureFeedURL, "relative URL rejected")
    },
    EngineCase("updates.config-missing-key-disables") {
        var info = updateSourceInfo()
        info.removeValue(forKey: "SUPublicEDKey")
        try expectEqual(UpdateConfiguration.from(infoDictionary: info).unavailableReason,
                        .missingPublicKey, "no key -> disabled")
    },
    EngineCase("updates.config-invalid-key-disables") {
        for bad in ["not-base64!!", "YWJj", "AAAA"] {
            var info = updateSourceInfo()
            info["SUPublicEDKey"] = bad
            let c = UpdateConfiguration.from(infoDictionary: info)
            try expectEqual(c.isUsable, false, "key \(bad) must be rejected")
            try expectEqual(c.unavailableReason, .invalidPublicKey, "typed reason")
        }
    },
    EngineCase("updates.config-empty-dictionary-disables") {
        let c = UpdateConfiguration.from(infoDictionary: [:])
        try expectEqual(c.isUsable, false, "no metadata -> disabled")
        try expectEqual(c.unavailableReason, .missingFeedURL, "first missing key wins")
        try expectEqual(c.bundleVersion, nil, "no version")
    },
    EngineCase("updates.reason-l10n-keys") {
        for reason in [UpdateUnavailableReason.notPackaged, .missingFeedURL,
                       .insecureFeedURL, .missingPublicKey, .invalidPublicKey] {
            try expectEqual(reason.l10nKey, "updates.unavailable.\(reason.rawValue)", "key shape")
        }
    },
]

// MARK: - localization

private let updateLocalizationCases: [EngineCase] = [
    EngineCase("updates.l10n-six-languages") {
        try expectEqual(AppLanguage.allCases.count, 6, "six languages")
        let required = ["updates.group", "updates.checkNow", "updates.auto",
                        "updates.autoCap", "updates.checkNowShort", "updates.unavailable",
                        "updates.unavailable.notPackaged", "updates.unavailable.missingFeedURL",
                        "updates.unavailable.insecureFeedURL", "updates.unavailable.missingPublicKey",
                        "updates.unavailable.invalidPublicKey"]
        for lang in AppLanguage.allCases {
            var keys = Set<String>()
            for key in required {
                let value = L10n.t(key, language: lang)
                try expectEqual(value == key, false, "\(lang.rawValue) missing \(key)")
                try expectEqual(value.isEmpty, false, "\(lang.rawValue) empty \(key)")
                keys.insert(key)
            }
            try expectEqual(keys.count, required.count, "\(lang.rawValue) coverage")
        }
    },
    EngineCase("updates.l10n-secure-wording") {
        // r96: the generic security paragraph is no longer UI prose — the
        // HTTPS/signature guarantee lives in the implementation, the
        // packaging policy scripts and docs/UPDATES.md. The retired key
        // must be gone in every language, and the remaining updater keys
        // must still be translated.
        for lang in AppLanguage.allCases {
            try expectEqual(L10n.t("updates.secure", language: lang), "updates.secure",
                            "\(lang.rawValue): the retired security caption is gone")
        }
    },
    EngineCase("updates.l10n-key-parity") {
        // The updater block is complete in every language: no language may
        // silently fall back to English for an updater string.
        let updaterKeys = Set(L10n.translations[.en]!.keys.filter { $0.hasPrefix("updates.") })
        try expectEqual(updaterKeys.count, 11, "eleven updater keys in en")
        for (lang, table) in L10n.translations {
            let missing = updaterKeys.subtracting(table.keys)
            try expectEqual(missing.isEmpty, true, "\(lang.rawValue) missing \(missing.sorted())")
        }
    },
]

// MARK: - source invariants

private let updateSourceInvariantCases: [EngineCase] = [
    EngineCase("updates.source-uses-standard-sparkle-controller") {
        guard let source = updateRepoFile("Sources/NumlexApp/UpdateController.swift") else {
            throw CaseFailure(message: "UpdateController.swift missing")
        }
        try expectEqual(source.contains("SPUStandardUpdaterController"), true, "standard controller")
        try expectEqual(source.contains("startingUpdater: true"), true, "starts the updater")
        try expectEqual(source.contains("canCheckForUpdates"), true, "availability flag")
        try expectEqual(source.contains("automaticallyChecksForUpdates"), true, "Sparkle setting")
        // No hand-rolled updater UI: the layer must not create windows/alerts.
        for banned in ["NSAlert(", "NSWindow(", "URLSession("] {
            try expectEqual(source.contains(banned), false, "no custom updater surface: \(banned)")
        }
    },
    EngineCase("updates.source-graceful-disable") {
        guard let source = updateRepoFile("Sources/NumlexApp/UpdateController.swift") else {
            throw CaseFailure(message: "UpdateController.swift missing")
        }
        try expectEqual(source.contains("UpdateConfiguration.isPackagedApp(bundle: bundle)"), true,
                        "packaged-bundle gate")
        try expectEqual(source.contains("configuration.unavailableReason"), true, "typed reason gate")
        // The controller must be created only after both gates pass.
        let gate = source.range(of: "unavailableReason")
        let create = source.range(of: "SPUStandardUpdaterController(")
        try expectEqual(gate != nil && create != nil && gate!.lowerBound < create!.lowerBound, true,
                        "gates run before the controller is constructed")
    },
    EngineCase("updates.source-runtime-state-not-in-app-settings") {
        guard let settings = updateRepoFile("Sources/NumlexCore/Models/Settings.swift") else {
            throw CaseFailure(message: "Settings.swift missing")
        }
        // Sparkle owns the automatic-check preference in its own
        // UserDefaults; it must never be duplicated into the app store.
        try expectEqual(settings.contains("automaticallyChecksForUpdates"), false,
                        "AppSettings must not carry Sparkle state")
        try expectEqual(settings.contains("SUFeedURL"), false, "feed URL is not an app setting")
        guard let model = updateRepoFile("Sources/NumlexApp/AppModel.swift") else {
            throw CaseFailure(message: "AppModel.swift missing")
        }
        try expectEqual(model.contains("automaticallyChecksForUpdates"), false,
                        "AppModel must not cache Sparkle state")
    },
    EngineCase("updates.source-menu-item-after-about") {
        guard let app = updateRepoFile("Sources/NumlexApp/NumlexApp.swift") else {
            throw CaseFailure(message: "NumlexApp.swift missing")
        }
        try expectEqual(app.contains("CommandGroup(after: .appInfo)"), true, "app-menu placement")
        try expectEqual(app.contains("updates.checkNow"), true, "localized title")
        try expectEqual(app.contains("model.updates.checkForUpdates()"), true, "standard action")
    },
    EngineCase("updates.source-settings-group") {
        guard let view = updateRepoFile("Sources/NumlexApp/Views/SettingsView.swift") else {
            throw CaseFailure(message: "SettingsView.swift missing")
        }
        // r92: the update controls live on the About page (app identity
        // + update controls in one calm page); the page has no subtitle
        // and no duplicated title/button pair.
        try expectEqual(view.contains("AboutSettingsPage"), true, "About page owns the controls")
        try expectEqual(view.contains("UpdatesSettingsPage"), false, "the Updates page is gone")
        try expectEqual(view.contains("destination: .about"), true, "About destination")
        try expectEqual(view.contains("model.updates.checkForUpdates()"), true, "manual check")
        try expectEqual(view.contains("setAutomaticallyChecksForUpdates"), true, "automatic toggle")
        try expectEqual(view.contains("updates.secure"), false,
                        "the generic security caption is no longer UI prose")
        try expectEqual(view.contains("updates.checkNowShort"), true, "one check action")
        try expectEqual(view.contains("updates.unavailable"), true, "disabled explanation")
    },
    EngineCase("updates.source-package-pin") {
        guard let manifest = updateRepoFile("Package.swift") else {
            throw CaseFailure(message: "Package.swift missing")
        }
        try expectEqual(manifest.contains("https://github.com/sparkle-project/Sparkle"), true, "repo")
        try expectEqual(manifest.contains("exact: \"2.9.6\""), true, "exact stable pin")
        try expectEqual(manifest.contains("2.10"), false, "no beta pin")
        try expectEqual(manifest.contains(".product(name: \"Sparkle\", package: \"Sparkle\")"), true,
                        "product link")
        // Only the app target may link Sparkle: the product reference lives
        // inside the NumlexApp target block (between its declaration and the
        // following NumlexTestKit target).
        let productLine = ".product(name: \"Sparkle\", package: \"Sparkle\")"
        try expectEqual(manifest.components(separatedBy: productLine).count - 1, 1,
                        "exactly one Sparkle product reference")
        if let appDecl = manifest.range(of: "name: \"NumlexApp\"", options: .backwards),
           let testKit = manifest.range(of: "name: \"NumlexTestKit\"", options: .backwards),
           let product = manifest.range(of: productLine) {
            try expectEqual(product.lowerBound > appDecl.lowerBound && product.lowerBound < testKit.lowerBound,
                            true, "Sparkle product belongs to the app target")
        }
    },
    EngineCase("updates.install-policy-eddsa-not-identity") {
        // The published policy: EdDSA (mandatory, pre-extraction verified) is
        // the trust route; the Apple identity-matching route is unavailable
        // for ad-hoc builds and is NOT required.
        let proof = try runUpdatePolicyProof()
        try expectEqual(proof.oldCDHashRequirement.hasPrefix("cdhash"), true,
                        "ad-hoc designated requirement is cdhash-based")
        try expectEqual(proof.identityRouteMatches, false,
                        "Apple identity matching cannot match two ad-hoc builds")
        try expectEqual(proof.intactArchiveVerifies, true,
                        "Ed25519 verifies the intact archive")
        try expectEqual(proof.corruptedArchiveVerifies, false,
                        "Ed25519 rejects a corrupted archive")
        guard let plist = updateRepoFile("Sources/NumlexApp/Resources/Info.plist") else {
            throw CaseFailure(message: "Info.plist missing")
        }
        try expectEqual(plist.contains("<key>SUPublicEDKey</key><string>"), true,
                        "the EdDSA public key is the app's trust anchor")
        try expectEqual(plist.contains("<key>SUVerifyUpdateBeforeExtraction</key><true/>"), true,
                        "archives are verified before extraction (prevalidated path)")
        guard let policyScript = updateRepoFile("Scripts/verify-sparkle-policy.sh") else {
            throw CaseFailure(message: "verify-sparkle-policy.sh missing")
        }
        try expectEqual(policyScript.contains("passedDSACheck || passedCodeSigning"), true,
                        "the policy guard asserts Sparkle's acceptance predicate")
        try expectEqual(policyScript.contains("andMatchesSignatureAtBundleURL:"), true,
                        "the policy guard asserts where the identity match lives")
        try expectEqual(policyScript.contains("944a7ba53e49ebb0f7cf38e2228d38def9b70738cf2f4b7c5dd63a8d826ce465"), true,
                        "the pinned validator digest is recorded")
    },
    EngineCase("updates.source-info-plist-keys") {
        guard let plist = updateRepoFile("Sources/NumlexApp/Resources/Info.plist") else {
            throw CaseFailure(message: "Info.plist missing")
        }
        try expectEqual(plist.contains("<key>SUFeedURL</key><string>https://numlex.tech/appcast.xml</string>"),
                        true, "https feed URL")
        try expectEqual(plist.contains("<key>SUPublicEDKey</key><string>"), true, "public key present")
        try expectEqual(plist.contains("<key>SUVerifyUpdateBeforeExtraction</key><true/>"), true,
                        "pre-extraction verification")
        try expectEqual(plist.contains("<key>SUEnableSystemProfiling</key><false/>"), true,
                        "profiling off")
        try expectEqual(plist.contains("SURequireSignedFeed"), false,
                        "signed feed deliberately not claimed")
        try expectEqual(plist.contains("SUSendsSystemProfile"), false, "legacy key not used")
    },
    EngineCase("updates.source-build-script-parity") {
        guard let script = updateRepoFile("Scripts/build-app.sh") else {
            throw CaseFailure(message: "build-app.sh missing")
        }
        // The packaged plist must carry the SAME Sparkle keys as the source
        // plist, embedded with the framework and verified before shipping.
        for needle in ["SUFeedURL", "SUPublicEDKey", "SUVerifyUpdateBeforeExtraction",
                       "SUEnableSystemProfiling"] {
            try expectEqual(script.contains(needle), true, "packaged plist key \(needle)")
        }
        try expectEqual(script.contains("Sparkle.framework"), true, "framework embedding")
        try expectEqual(script.contains("@loader_path/../Frameworks"), true, "rpath")
        // The signing comment must describe the real policy: EdDSA is the
        // trust route and ad-hoc is supported; NUMLEX_SIGN_IDENTITY stays an
        // optional override, never a requirement.
        try expectEqual(script.contains("stable identity is NOT required"), true,
                        "build script documents that no stable identity is required")
        try expectEqual(script.contains("NUMLEX_SIGN_IDENTITY"), true, "override preserved")
    },
]
