import Foundation
import CryptoKit

// Ed25519 (Sparkle EdDSA) verification for update archives and appcasts.
//
// Usage:
//   swift Scripts/verify-ed25519.swift <file> <base64-signature> <base64-public-key>
//
// Verifies the raw file bytes against a 64-byte Ed25519 signature using the
// 32-byte public key. Exits 0 on success, 1 on any failure, and prints only
// verdict data (never key material beyond the public key it was given).

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("verify-ed25519: \(message)\n".utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count == 4 else {
    fail("usage: verify-ed25519.swift <file> <base64-signature> <base64-public-key>")
}

guard let signature = Data(base64Encoded: args[2]), signature.count == 64 else {
    fail("signature is not base64 of 64 bytes")
}
guard let publicKeyData = Data(base64Encoded: args[3]), publicKeyData.count == 32 else {
    fail("public key is not base64 of 32 bytes")
}
guard let fileData = FileManager.default.contents(atPath: args[1]) else {
    fail("cannot read \(args[1])")
}

do {
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
    guard key.isValidSignature(signature, for: fileData) else {
        fail("signature does not match the archive")
    }
} catch {
    fail("invalid public key: \(error)")
}

print("verify-ed25519: OK (\(fileData.count) bytes)")
