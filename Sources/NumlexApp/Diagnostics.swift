import Foundation

/// r77c: opt-in event-chain tracing for validation. Enabled ONLY by the
/// launch argument `--trace <dir>` (inert without it — no timers, no
/// I/O, no behavior change). Appends one timestamped line per event to
/// `<dir>/trace.log`, covering the complete answer-double-click chain
/// (catcher mouseDown → row mapping → model insertion → editor rebind)
/// and the answer-motion pass lifecycle, so a live failure can be
/// traced in the real UI instead of being guessed from state machines.
@MainActor
final class Diagnostics {
    nonisolated(unsafe) static var shared: Diagnostics?

    private let dirURL: URL
    private var handle: FileHandle?
    private let started = ProcessInfo.processInfo.systemUptime

    private init(dirURL: URL) {
        self.dirURL = dirURL
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        let p = dirURL.appendingPathComponent("trace.log")
        if !FileManager.default.fileExists(atPath: p.path) {
            FileManager.default.createFile(atPath: p.path, contents: Data())
        }
        handle = try? FileHandle(forWritingTo: p)
    }

    static func startIfRequested() -> Diagnostics? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--trace"), i + 1 < args.count else { return nil }
        let d = Diagnostics(dirURL: URL(fileURLWithPath: args[i + 1], isDirectory: true))
        d.log("start args=\(args.joined(separator: " "))")
        shared = d
        return d
    }

    func log(_ s: String) {
        guard let h = handle, let d = (String(format: "t=%.4f %@", ProcessInfo.processInfo.systemUptime - started, s) + "\n").data(using: .utf8) else { return }
        h.write(d)
    }

    func finish() {
        log("finish")
        handle?.closeFile()
    }
}
