import Foundation

/// The pure, dependency-free description of how this build can talk to the
/// update feed (Sparkle 2.9.6 contract).
///
/// The app target owns the Sparkle integration (`SPUStandardUpdaterController`);
/// this type owns the *decision* whether that integration may start at all, so
/// the rule is unit-testable without linking Sparkle and so a development run
/// (`swift run Numlex`, no packaged `.app`) degrades gracefully instead of
/// crashing.
///
/// Verified keys (Sparkle 2.9.6):
///   - `SUFeedURL`               — HTTPS appcast URL,
///   - `SUPublicEDKey`           — base64 Ed25519 public key (32 bytes),
///   - `SUVerifyUpdateBeforeExtraction` — archive verified before extraction,
///   - `SUEnableSystemProfiling` — anonymous profiling (must stay off).
public struct UpdateConfiguration: Equatable, Sendable {
    /// Feed URL exactly as declared (`nil` = key missing/unreadable).
    public let feedURL: URL?
    /// Base64 public key exactly as declared (`nil` = key missing).
    public let publicEDKey: String?
    /// `SUVerifyUpdateBeforeExtraction` (default in Sparkle is false).
    public let verifiesBeforeExtraction: Bool
    /// `SUEnableSystemProfiling` (default in Sparkle is false).
    public let systemProfilingEnabled: Bool
    /// `CFBundleVersion` of the host, when packaged.
    public let bundleVersion: String?

    public init(feedURL: URL?,
                publicEDKey: String?,
                verifiesBeforeExtraction: Bool,
                systemProfilingEnabled: Bool,
                bundleVersion: String?) {
        self.feedURL = feedURL
        self.publicEDKey = publicEDKey
        self.verifiesBeforeExtraction = verifiesBeforeExtraction
        self.systemProfilingEnabled = systemProfilingEnabled
        self.bundleVersion = bundleVersion
    }

    /// Reads the four Sparkle keys from a bundle Info.plist dictionary.
    /// Missing keys become `nil`/`false` — never a crash, never a guess.
    public static func from(infoDictionary info: [String: Any]) -> UpdateConfiguration {
        let rawFeed = (info["SUFeedURL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return UpdateConfiguration(
            feedURL: (rawFeed?.isEmpty == false) ? URL(string: rawFeed!) : nil,
            publicEDKey: (info["SUPublicEDKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            verifiesBeforeExtraction: (info["SUVerifyUpdateBeforeExtraction"] as? Bool) ?? false,
            systemProfilingEnabled: (info["SUEnableSystemProfiling"] as? Bool) ?? false,
            bundleVersion: info["CFBundleVersion"] as? String
        )
    }

    /// Reads the configuration from a bundle (`.main` in the app).
    public static func from(bundle: Bundle) -> UpdateConfiguration {
        from(infoDictionary: bundle.infoDictionary ?? [:])
    }

    /// True when the public key is a decodable 32-byte Ed25519 key.
    public var hasValidPublicKey: Bool {
        guard let key = publicEDKey, let data = Data(base64Encoded: key) else { return false }
        return data.count == 32
    }

    /// True when the feed URL is present, absolute, HTTPS and has a host.
    public var hasUsableFeedURL: Bool {
        guard let url = feedURL, let scheme = url.scheme?.lowercased(), let host = url.host else { return false }
        return scheme == "https" && !host.isEmpty
    }

    /// The reason the updater must stay disabled (nil = it may start).
    public var unavailableReason: UpdateUnavailableReason? {
        if !hasUsableFeedURL {
            return feedURL == nil ? .missingFeedURL : .insecureFeedURL
        }
        if !hasValidPublicKey {
            return publicEDKey == nil ? .missingPublicKey : .invalidPublicKey
        }
        return nil
    }

    /// True when the Sparkle updater may be constructed and started.
    public var isUsable: Bool { unavailableReason == nil }

    /// True when this process runs from a packaged `.app` bundle with an
    /// identifier (the update contract requires a real bundle).
    public static func isPackagedApp(bundle: Bundle = .main) -> Bool {
        bundle.bundleIdentifier != nil && bundle.bundleURL.pathExtension == "app"
    }
}

/// Why the updater is disabled in this process (typed, localized by the UI).
public enum UpdateUnavailableReason: String, Equatable, Sendable {
    /// No `SUFeedURL` (a development build without packaged metadata).
    case missingFeedURL
    /// `SUFeedURL` is not an absolute HTTPS URL.
    case insecureFeedURL
    /// No `SUPublicEDKey`.
    case missingPublicKey
    /// `SUPublicEDKey` is not a base64 32-byte Ed25519 key.
    case invalidPublicKey
    /// The process is not a packaged `.app` (for example `swift run Numlex`).
    case notPackaged

    /// Stable L10n key suffix for the reason ("updates.unavailable.<raw>").
    public var l10nKey: String { "updates.unavailable.\(rawValue)" }
}
