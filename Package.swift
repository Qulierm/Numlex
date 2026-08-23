// swift-tools-version: 6.0
import PackageDescription
import Foundation

// The Swift Testing framework ships with the macOS developer toolchain under
// .../Library/Developer/Frameworks, but SwiftPM does not add that search path
// automatically when building with raw Command Line Tools. Locate it so the
// test target compiles (and links) on both CLTools and full Xcode.
let testingFrameworks: String? = {
    let env = ProcessInfo.processInfo.environment["NUMLEX_TESTING_FRAMEWORKS"]
    let candidates = ([env] + [
        "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
        "/Applications/Xcode.app/Contents/Developer/Library/Frameworks",
    ]).compactMap { $0 }
    return candidates.first { FileManager.default.fileExists(atPath: "\($0)/Testing.framework") }
}()

let testingFlags: [String] = testingFrameworks.map { ["-F", $0, "-framework", "Testing"] } ?? []
let testingSwiftSettings: [SwiftSetting] = testingFlags.isEmpty ? [] : [.unsafeFlags(testingFlags)]
let testingLinkerSettings: [LinkerSetting] = testingFlags.isEmpty ? [] : [.unsafeFlags(testingFlags)]

let package = Package(
    name: "Numlex",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "Numlex", targets: ["NumlexApp"]),
        .library(name: "NumlexCore", targets: ["NumlexCore"]),
    ],
    targets: [
        .target(
            name: "NumlexCore",
            path: "Sources/NumlexCore"
        ),
        .executableTarget(
            name: "NumlexApp",
            dependencies: ["NumlexCore"],
            path: "Sources/NumlexApp",
            // Consumed by Scripts/build-app.sh when assembling Numlex.app.
            exclude: ["Resources/Info.plist"]
        ),
        // Shared, portable test cases (no test-framework dependency).
        .target(
            name: "NumlexTestKit",
            dependencies: ["NumlexCore"],
            path: "Tests/NumlexTestKit"
        ),
        // Swift Testing suite: `swift test` on a full Xcode toolchain.
        .testTarget(
            name: "NumlexCoreTests",
            dependencies: ["NumlexCore", "NumlexTestKit"],
            path: "Tests/NumlexCoreTests",
            swiftSettings: testingSwiftSettings,
            linkerSettings: testingLinkerSettings
        ),
        // Standalone runner for CLTools-only machines: `swift run NumlexTests`.
        .executableTarget(
            name: "NumlexTests",
            dependencies: ["NumlexTestKit"],
            path: "Tests/NumlexTests"
        ),
    ]
)
