//
//  PlainDMGCases.swift
//  NumlexTestKit
//
//  The DMG contract is PLAIN: the installer image is a one-shot read-only
//  UDZO/HFS+ volume containing exactly Numlex.app and an Applications
//  shortcut. These source-level cases pin the plain default and fail if any
//  styled-DMG hook (Finder scripting, generated backgrounds, volume icons,
//  layout metadata or a "-plain" opt-out) ever returns.
//

import Foundation

public var plainDMGCases: [EngineCase] {
    plainDMGBuildCases + plainDMGValidatorCases + plainDMGArtifactCases + plainDMGDocsCases
}

private func plainRepoRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // NumlexTestKit
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repo root
}

private func plainRepoText(_ rel: String) -> String? {
    let url = plainRepoRoot().appendingPathComponent(rel).standardizedFileURL
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try? String(contentsOf: url, encoding: .utf8)
}

private func plainRepoExists(_ rel: String) -> Bool {
    FileManager.default.fileExists(atPath: plainRepoRoot().appendingPathComponent(rel).path)
}

/// Executable lines only: comments may name the forbidden patterns while
/// explaining the contract, but a real hook must never survive here.
private func plainExecutableLines(_ text: String) -> String {
    text.split(separator: "\n", omittingEmptySubsequences: false)
        .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
        .joined(separator: "\n")
}

private let plainForbiddenBuildTokens = [
    "configure-dmg-finder",
    "generate-dmg-background",
    "inject-srgb",
    ".background",
    "VolumeIcon",
    ".DS_Store",
    "osascript",
    "Finder",
    "--plain",
    "NUMLEX_PLAIN_DMG",
    "NUMLEX_STYLED",
]

private let plainDMGBuildCases: [EngineCase] = [
    EngineCase("plain-dmg-build-script-is-the-only-default") {
        guard let script = plainRepoText("Scripts/build-dmg.sh") else {
            throw CaseFailure(message: "Scripts/build-dmg.sh missing", location: "plain-dmg")
        }
        for required in [
            "set -euo pipefail",
            "NUMLEX_USE_BUILT_APP",
            "NUMLEX_DMG_OUTPUT",
            "hdiutil create",
            "-volname \"Numlex $VERSION\"",
            "-format UDZO",
            "-fs HFS+",
            "cp -R \"$APP_DIR\" \"$STAGE/Numlex.app\"",
            "ln -s /Applications \"$STAGE/Applications\"",
            "DMG_NAME=\"Numlex-${VERSION}-macOS-${ARCH}.dmg\"",
        ] {
            try expect(script.contains(required), "build-dmg.sh must contain: \(required)")
        }
        let executable = plainExecutableLines(script)
        for forbidden in plainForbiddenBuildTokens {
            try expect(!executable.contains(forbidden), "build-dmg.sh executable line uses styled hook: \(forbidden)")
        }
        // The output filename is the plain one: no "-plain" suffix exists in
        // the sanctioned pipeline, so both styled and opt-out markers fail.
        try expect(!executable.contains("plain.dmg"), "build-dmg.sh must not emit a '-plain' filename")
    },
    EngineCase("plain-dmg-build-script-stages-two-root-items") {
        guard let script = plainRepoText("Scripts/build-dmg.sh") else {
            throw CaseFailure(message: "Scripts/build-dmg.sh missing", location: "plain-dmg")
        }
        let executable = plainExecutableLines(script)
        // Only the app copy and the Applications symlink may write into the
        // staging directory: no artwork, metadata or extra items.
        let staged = executable.components(separatedBy: "\n").filter { $0.contains("$STAGE/") }
        try expect(staged.count == 2, "staging must write exactly the app and Applications (got \(staged.count) lines)")
        try expect(staged.contains { $0.contains("cp -R") && $0.contains("Numlex.app") }, "staging copies Numlex.app")
        try expect(staged.contains { $0.contains("ln -s /Applications") && $0.contains("Applications") }, "staging links Applications")
    },
]

private let plainDMGValidatorCases: [EngineCase] = [
    EngineCase("plain-dmg-validator-rejects-style-artifacts") {
        guard let script = plainRepoText("Scripts/validate-dmg.sh") else {
            throw CaseFailure(message: "Scripts/validate-dmg.sh missing", location: "plain-dmg")
        }
        for required in [
            "hdiutil verify",
            "Applications Numlex.app",
            ".background",
            ".DS_Store",
            ".VolumeIcon.icns",
            "com.numlex.app",
            "26.0",
            "arm64",
            "Sparkle.framework",
            "Downloader.xpc",
            "Installer.xpc",
            "Updater.app",
            "2.9.6",
            "be00c077a667c61da549c125efdde6e3d8448bb6bcf7b0f593777d6c6737ed1d",
            "NumlexTimezones/iana-zones.tsv",
            "NumlexHolidays/holidays.tsv",
            "NumlexIncomeTax/income-tax.json",
            "NumlexCPI/cpi-u.json",
            "NumlexTax/tax-presets.json",
        ] {
            try expect(script.contains(required), "validate-dmg.sh must contain: \(required)")
        }
        let executable = plainExecutableLines(script)
        for forbidden in [
            "osascript",
            "Finder",
            "configure-dmg-finder",
            "generate-dmg-background",
            "PIL",
            "Pillow",
            "iconutil",
        ] {
            try expect(!executable.contains(forbidden), "validate-dmg.sh executable line uses styled hook: \(forbidden)")
        }
    },
]

private let plainDMGArtifactCases: [EngineCase] = [
    EngineCase("styled-dmg-artifacts-are-gone") {
        let removed = [
            "Scripts/configure-dmg-finder.sh",
            "Scripts/generate-dmg-background.swift",
            "Scripts/inject-srgb-chunk.py",
            "Assets/DMG/README.md",
            "Assets/DMG/NumlexDMGBackground.png",
            "Assets/DMG/NumlexDMGBackground@2x.png",
        ]
        for path in removed {
            try expect(!plainRepoExists(path), "styled-DMG artifact must be removed: \(path)")
        }
        // The tagline PNG is a NON-style consumer (WEBSITE_BRIEF typography
        // reference) and must survive the cleanup.
        try expect(plainRepoExists("Assets/DMG/numlex-tagline.png"), "tagline asset must remain")
    },
]

private let plainDMGDocsCases: [EngineCase] = [
    EngineCase("app-docs-describe-a-plain-dmg") {
        guard let readme = plainRepoText("README.md") else {
            throw CaseFailure(message: "README.md missing", location: "plain-dmg")
        }
        try expect(readme.contains("drag **Numlex.app** into Applications"),
                   "README must document the drag-to-Applications DMG install")
        try expect(!readme.lowercased().contains("styled installer"),
                   "README must not advertise a styled DMG")
    },
    EngineCase("app-docs-never-mention-styled-dmg-scripts") {
        for path in ["README.md", "WEBSITE_BRIEF.md"] {
            guard let text = plainRepoText(path) else {
                throw CaseFailure(message: "\(path) missing", location: "plain-dmg")
            }
            for forbidden in ["configure-dmg-finder", "generate-dmg-background", "NumlexDMGBackground"] {
                try expect(!text.contains(forbidden), "\(path) must not reference styled DMG asset/script: \(forbidden)")
            }
        }
    },
]
