import Foundation
import CryptoKit

// Executable proof of the documented install policy: in-app installation
// does not require a stable Apple code-signing identity when the mandatory
// EdDSA archive signature validates.
//
//   1. two ad-hoc signed bundles with different contents have different
//      cdhash-based designated requirements, so Apple's identity-matching
//      route CANNOT match them (that route is therefore unusable, not
//      required);
//   2. the same archive bytes verify with Ed25519 signatures produced by one
//      key — the route Numlex mandates (SUPublicEDKey + pre-extraction
//      verification);
//   3. a corrupted archive fails that verification.
//
// Everything is generated in a temporary directory with a throwaway key; the
// production signing key and the pinned Sparkle sources are not touched.

/// Result of the two-bundle ad-hoc + Ed25519 policy proof.
struct UpdatePolicyProof {
    let oldCDHashRequirement: String
    let identityRouteMatches: Bool
    let intactArchiveVerifies: Bool
    let corruptedArchiveVerifies: Bool
}

func runUpdatePolicyProof() throws -> UpdatePolicyProof {
    let fm = FileManager.default
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("numlex-update-policy-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }

    func makeBundle(named name: String, payload: String) throws -> URL {
        let app = root.appendingPathComponent("\(name).app", isDirectory: true)
        let macos = app.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try fm.createDirectory(at: macos, withIntermediateDirectories: true)
        let executable = macos.appendingPathComponent("Numlex")
        try payload.data(using: .utf8)!.write(to: executable)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>CFBundleIdentifier</key><string>com.numlex.policy-proof</string>
        <key>CFBundleExecutable</key><string>Numlex</string>
        <key>CFBundleName</key><string>Numlex</string>
        <key>CFBundlePackageType</key><string>APPL</string>
        <key>CFBundleVersion</key><string>\(name)</string>
        <key>CFBundleShortVersionString</key><string>\(name)</string>
        </dict></plist>
        """
        try plist.data(using: .utf8)!.write(to: app.appendingPathComponent("Contents/Info.plist"))
        let sign = Process()
        sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        sign.arguments = ["--force", "--sign", "-", app.path]
        sign.standardOutput = Pipe(); sign.standardError = Pipe()
        try sign.run(); sign.waitUntilExit()
        guard sign.terminationStatus == 0 else {
            throw CaseFailure(message: "ad-hoc signing failed for \(name)")
        }
        return app
    }

    func designatedRequirement(of app: URL) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        p.arguments = ["-d", "-r-", app.path]
        let pipe = Pipe(); p.standardError = pipe; p.standardOutput = pipe
        try p.run(); p.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard let line = output.split(separator: "\n").first(where: { $0.contains("designated =>") }),
              let marker = line.range(of: "designated =>") else {
            throw CaseFailure(message: "no designated requirement in: \(output)")
        }
        // The line carries a comment marker before the requirement text.
        return line[marker.upperBound...].trimmingCharacters(in: .whitespaces)
    }

    func satisfies(_ requirement: String, app: URL) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        p.arguments = ["--verify", "-R=\(requirement)", app.path]
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()
        return p.terminationStatus == 0
    }

    func writeAndSign(_ name: String, payload: String) throws -> URL {
        let file = root.appendingPathComponent(name)
        try payload.data(using: .utf8)!.write(to: file)
        return file
    }

    let oldApp = try makeBundle(named: "1", payload: "old build payload")
    let newApp = try makeBundle(named: "2", payload: "new build payload")
    let requirement = try designatedRequirement(of: oldApp)
    // The identity route looks for the OLD bundle's designated requirement in
    // the NEW bundle; for ad-hoc builds that requirement is cdhash-based.
    let identityMatches = satisfies(requirement, app: newApp)

    // The route Numlex mandates: one Ed25519 key over the archive bytes.
    let signingKey = Curve25519.Signing.PrivateKey()
    let publicKey = signingKey.publicKey
    let archive = try writeAndSign("Numlex-archive.dmg", payload: "archive bytes for the update")
    let archiveData = try Data(contentsOf: archive)
    let signature = try signingKey.signature(for: archiveData)
    let intactVerifies = publicKey.isValidSignature(signature, for: archiveData)

    var corrupted = archiveData
    corrupted[corrupted.startIndex] ^= 0xFF
    let corruptedVerifies = publicKey.isValidSignature(signature, for: corrupted)

    return UpdatePolicyProof(oldCDHashRequirement: requirement,
                             identityRouteMatches: identityMatches,
                             intactArchiveVerifies: intactVerifies,
                             corruptedArchiveVerifies: corruptedVerifies)
}
