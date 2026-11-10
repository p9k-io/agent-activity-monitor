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
    .executable(name: "aam", targets: ["aam"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.2")
  ],
  targets: [
    .target(name: "AAMCore", swiftSettings: settings),
    .target(name: "AAMPlatform", dependencies: ["AAMCore"], swiftSettings: settings),
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
    // A process the tests may start, inspect and end. It is never shipped.
    .executableTarget(name: "aam-test-helper", path: "Tests/TestHelper", swiftSettings: settings),
  ]
)
