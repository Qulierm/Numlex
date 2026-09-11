import Foundation

/// r97: the ONE first-launch policy for the welcome/onboarding screen.
///
/// The decision is deliberately FILE-PRESENCE based and lives entirely in
/// the app's data directory (the same directory as `store.json`), so the
/// `--data-dir` validation override isolates it automatically. It never
/// touches `store.json`, `AppSettings`, `UserDefaults` or `.nlx`, and it
/// never changes the store schema or version:
///
///   * no marker + no prior artifacts  -> welcome (a genuinely new install)
///   * prior artifacts, no marker      -> no welcome; record the marker
///     without modifying those artifacts (an existing user who never saved
///     an edit is still an existing user)
///   * marker present                  -> no welcome
///   * store.json present but CORRUPT  -> no welcome (presence, not
///     decodability, decides)
///
/// The completion marker is a tiny versioned file written ATOMICALLY and
/// idempotently. If it cannot be written the app still enters the main
/// window for this session and simply shows the welcome again next launch;
/// nothing here ever blocks the app.
public enum FirstLaunch {
    /// The versioned completion marker filename. A future onboarding change
    /// can introduce `welcome-v2` without touching existing installs (they
    /// would then see the new flow only if the new marker is absent AND no
    /// prior artifacts exist — i.e. only genuinely new installs, unless the
    /// policy is deliberately changed).
    public static let markerFileName = "welcome-v1"

    /// Every artifact that marks a directory as "an existing Numlex user".
    /// These are exactly the files the app keeps beside `store.json`
    /// (including the corrupt/unreadable cases — only presence matters).
    public static let artifactFileNames: [String] = [
        "store.json",
        "rates.json",
        "weather.json",
        "locations.json",
    ]

    /// Whether the completion marker exists.
    public static func isCompleted(in directory: URL,
                                   fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(
            atPath: directory.appendingPathComponent(markerFileName).path)
    }

    /// Whether the directory already carries any known Numlex artifact.
    public static func hasPriorArtifacts(in directory: URL,
                                         fileManager: FileManager = .default) -> Bool {
        artifactFileNames.contains { name in
            fileManager.fileExists(atPath: directory.appendingPathComponent(name).path)
        }
    }

    /// THE decision: show the welcome only for a genuinely empty directory.
    public static func shouldShowWelcome(in directory: URL,
                                         fileManager: FileManager = .default) -> Bool {
        !isCompleted(in: directory, fileManager: fileManager)
            && !hasPriorArtifacts(in: directory, fileManager: fileManager)
    }

    /// The LAUNCH entry point: the decision plus the ONE allowed migration
    /// effect. For an existing install (any prior artifact) the completion
    /// marker is recorded best-effort WITHOUT touching those artifacts, so
    /// a user who later deletes a cache file is never suddenly treated as
    /// brand new. A genuinely empty directory returns true and records
    /// nothing (the marker is written only when the user actually starts).
    public static func evaluateAtLaunch(in directory: URL,
                                        fileManager: FileManager = .default) -> Bool {
        if isCompleted(in: directory, fileManager: fileManager) { return false }
        if hasPriorArtifacts(in: directory, fileManager: fileManager) {
            _ = markCompleted(in: directory, fileManager: fileManager)
            return false
        }
        return true
    }

    /// Records completion atomically. Returns false when the write failed
    /// (the caller still enters the app; the welcome simply reappears on the
    /// next launch). Idempotent: calling it twice is harmless.
    @discardableResult
    public static func markCompleted(in directory: URL,
                                     fileManager: FileManager = .default) -> Bool {
        let url = directory.appendingPathComponent(markerFileName)
        let data = Data("1\n".utf8)
        do {
            try fileManager.createDirectory(at: directory,
                                            withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
