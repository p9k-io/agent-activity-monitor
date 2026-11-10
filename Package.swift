// swift-tools-version: 6.2
import PackageDescription

let settings: [SwiftSetting] = [
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  .enableUpcomingFeature("InferIsolatedConformances"),
  .enableUpcomingFeature("ExistentialAny"),
]

let package = Package(
  name: "agent-activity-monitor",
  platforms: [.macOS(.v26)],
  products: [
    .library(name: "AAMCore", targets: ["AAMCore"]),
    .library(name: "AAMPlatform", targets: ["AAMPlatform"]),
    .library(name: "AAMCleanup", targets: ["AAMCleanup"]),
    .library(name: "AAMUpdates", targets: ["AAMUpdates"]),
    .executable(name: "aam", targets: ["aam"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.2"),
    // Declared here, not in the app's project, so that the package and the app share one
    // Package.resolved instead of each rewriting the other's.
    .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
  ],
  targets: [
    .target(name: "AAMCore", swiftSettings: settings),
    .target(name: "AAMPlatform", dependencies: ["AAMCore"], swiftSettings: settings),
    // Ends processes. Only the app links it: the command line tool must not, so that it cannot
    // end anything (docs/adr/0001).
    .target(
      name: "AAMCleanup", dependencies: ["AAMCore", "AAMPlatform"], swiftSettings: settings),
    // Looks for updates and installs them. Only the app links it.
    .target(
      name: "AAMUpdates", dependencies: [.product(name: "Sparkle", package: "Sparkle")],
      swiftSettings: settings),
    .executableTarget(
      name: "aam",
      dependencies: [
        "AAMCore",
        "AAMPlatform",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      swiftSettings: settings
    ),
    .testTarget(name: "AAMCoreTests", dependencies: ["AAMCore"], swiftSettings: settings),
    .testTarget(
      name: "AAMPlatformTests",
      dependencies: ["AAMCore", "AAMPlatform", "aam", "aam-test-helper"],
      swiftSettings: settings
    ),
    .testTarget(
      name: "AAMCleanupTests",
      dependencies: ["AAMCore", "AAMPlatform", "AAMCleanup", "aam-test-helper"],
      swiftSettings: settings
    ),
    // A process the tests may start, inspect and end. It is never shipped.
    .executableTarget(name: "aam-test-helper", path: "Tests/TestHelper", swiftSettings: settings),
  ]
)
