import AppKit
import Foundation

/// r77b: instrumented motion-evidence harness, enabled ONLY by the
/// launch argument `--motion-evidence <dir>` (compiled into release
/// builds; completely inert without the flag — no timers, no logging,
/// no behavior change). While launched with the flag it:
/// - appends one line per answer-tick (60 Hz) with the exact in-flight
///   opacities to `<dir>/evidence.log` (timestamp, count, per-line
///   values) — the authoritative high-frame-rate record of the fade;
/// - captures the app's own main window content (in-process
///   `cacheDisplay` — own-window capture needs no screen-recording
///   permission, and no deprecated system-wide window-list API) to
///   `frame-NNNN-<t>s.png` — ambient ~2 Hz plus a 30 Hz burst for 0.6 s
///   whenever an answer appearance pass starts. The PNG encode runs on
///   a background queue off a Sendable pixel copy, so the main run
///   loop — and the animation it drives — is never starved.
/// Validation launches the bundle with an isolated HOME so the harness
/// never touches the real Application Support or defaults.
@MainActor
final class MotionEvidence {
    /// All access happens on the main thread (launch hook, answer
    /// ticks, timers on the main run loop); the background queue only
    /// ever consumes Sendable pixel copies, so the marker is safe in
    /// practice.
    nonisolated(unsafe) static var shared: MotionEvidence?

    private let dirURL: URL
    private var logHandle: FileHandle?
    private var ambientTimer: Timer?
    private var burstTimer: Timer?
    private var burstUntil: TimeInterval = 0
    private var frameSeq = 0
    private let captureQueue = DispatchQueue(label: "numlex.motion-evidence")
    private let started = ProcessInfo.processInfo.systemUptime

    private init(dirURL: URL) {
        self.dirURL = dirURL
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        let logPath = dirURL.appendingPathComponent("evidence.log")
        if !FileManager.default.fileExists(atPath: logPath.path) {
            FileManager.default.createFile(atPath: logPath.path, contents: Data())
        }
        logHandle = try? FileHandle(forWritingTo: logPath)
        // Ambient before/after frames (~2 Hz).
        ambientTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.log(String(format: "ambient t=%.4f",
                                 ProcessInfo.processInfo.systemUptime - (self?.started ?? 0)))
                self?.captureWindow()
            }
        }
        if let t = ambientTimer { RunLoop.main.add(t, forMode: .common) }
    }

    /// Parses the launch arguments; returns the harness (and sets
    /// `shared`) only when `--motion-evidence <dir>` is present.
    static func startIfRequested() -> MotionEvidence? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--motion-evidence"), i + 1 < args.count else {
            return nil
        }
        let harness = MotionEvidence(dirURL: URL(fileURLWithPath: args[i + 1], isDirectory: true))
        harness.log("start dir=\(harness.dirURL.path) args=\(args.joined(separator: " "))")
        shared = harness
        return harness
    }

    /// An appearance pass just started (answer or token): capture the
    /// window at 30 Hz for 0.6 s so the mid-fade frames are on disk.
    func noteBurst() {
        burstUntil = ProcessInfo.processInfo.systemUptime + 0.6
        guard burstTimer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if ProcessInfo.processInfo.systemUptime < self.burstUntil {
                    self.captureWindow()
                } else {
                    self.burstTimer?.invalidate()
                    self.burstTimer = nil
                }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        burstTimer = t
        captureWindow()
    }

    /// One 60 Hz sample from the answer tick: the exact opacities of
    /// every in-flight line, plus a burst-window frame capture.
    func sample(opacities: [UUID: Double], now: TimeInterval) {
        let values = opacities
            .sorted { $0.key.uuidString < $1.key.uuidString }
            .map { "\($0.key.uuidString.prefix(4))=\(String(format: "%.3f", $0.value))" }
            .joined(separator: " ")
        log(String(format: "sample t=%.4f n=%d %@", now - started, opacities.count,
                   values.isEmpty ? "-" : values))
        if now < burstUntil {
            captureWindow()
        }
    }

    func finish() {
        ambientTimer?.invalidate()
        burstTimer?.invalidate()
        if let h = logHandle {
            log("finish")
            h.closeFile()
        }
    }

    // MARK: - internals

    private func log(_ s: String) {
        guard let h = logHandle, let d = (s + "\n").data(using: .utf8) else { return }
        h.write(d)
    }

    /// Snapshot the window content on the main thread (a cheap
    /// in-process `cacheDisplay`), stamp the frame on the main thread,
    /// copy the pixels to a Sendable `Data`, then PNG-encode + write
    /// on the background queue. No mutable state crosses the thread
    /// boundary: each in-flight encode owns its pre-assigned sequence
    /// number and file name, so encodes never collide and the main
    /// run loop — and the animation it drives — is never starved.
    private func captureWindow() {
        guard let window = NSApp.windows
            .filter({ $0.isVisible && $0.styleMask.contains(.titled) && $0.frame.width > 400 })
            .max(by: {
                $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height
            }),
            let contentView = window.contentView
        else { return }
        let bounds = contentView.bounds
        guard let rep = contentView.bitmapImageRepForCachingDisplay(in: bounds) else {
            return
        }
        contentView.cacheDisplay(in: bounds, to: rep)
        guard let raw = rep.bitmapData else { return }
        // Sendable snapshot of the pixel buffer + format, stamped on
        // the main thread at the capture instant.
        let pixels = Data(bytes: raw, count: rep.bytesPerRow * rep.pixelsHigh)
        let wide = rep.pixelsWide
        let high = rep.pixelsHigh
        let bytesPerRow = rep.bytesPerRow
        let samplesPerPixel = rep.samplesPerPixel
        let bitsPerSample = rep.bitsPerSample
        let hasAlpha = rep.hasAlpha
        let isPlanar = rep.isPlanar
        let logDir = dirURL
        let t = ProcessInfo.processInfo.systemUptime - started
        frameSeq += 1
        let seq = frameSeq
        captureQueue.async { [pixels, wide, high, bytesPerRow,
                              samplesPerPixel, bitsPerSample, hasAlpha, isPlanar, logDir, t, seq] in
            guard let rebuilt = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: wide,
                pixelsHigh: high,
                bitsPerSample: bitsPerSample,
                samplesPerPixel: samplesPerPixel,
                hasAlpha: hasAlpha,
                isPlanar: isPlanar,
                colorSpaceName: .deviceRGB,
                bytesPerRow: bytesPerRow,
                bitsPerPixel: bitsPerSample * samplesPerPixel
            ) else { return }
            pixels.withUnsafeBytes { buf in
                if let dst = rebuilt.bitmapData {
                    memcpy(dst, buf.baseAddress!, buf.count)
                }
            }
            guard let data = rebuilt.representation(using: .png, properties: [:]) else { return }
            try? data.write(to: logDir.appendingPathComponent(
                String(format: "frame-%04d-%05.2fs.png", seq, t)))
        }
    }
}
