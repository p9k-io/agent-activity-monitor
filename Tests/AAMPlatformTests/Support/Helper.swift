import Darwin
import Foundation

/// Starts the test helper, a process these tests own and may end.
enum Helper {
  /// The helper is built next to the test bundle. The bundle is found among the loaded images,
  /// because the test runner's own main bundle is the toolchain's.
  static let url: URL = {
    for index in 0..<_dyld_image_count() {
      guard let name = _dyld_get_image_name(index) else { continue }
      let image = String(cString: name)
      if let bundle = image.range(of: ".xctest/") {
        return URL(fileURLWithPath: String(image[..<bundle.lowerBound]))
          .deletingLastPathComponent()
          .appendingPathComponent("aam-test-helper")
      }
    }
    return URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent(".build/debug/aam-test-helper")
  }()

  static func sleeping(
    seconds: Int = 30,
    environment: [String: String] = [:],
    in directory: URL? = nil
  ) throws -> Process {
    let process = Process()
    process.executableURL = url
    process.arguments = ["sleep", String(seconds)]
    process.environment = environment
    process.currentDirectoryURL = directory
    try process.run()
    return process
  }

  /// Starts the helper in the mode that turns into `/bin/sleep` when a byte arrives on its
  /// standard input. Returns the process and the pipe to write that byte to.
  static func becomingSleep(seconds: Int = 30) throws -> (process: Process, trigger: Pipe) {
    let process = Process()
    let trigger = Pipe()
    process.executableURL = url
    process.arguments = ["become-sleep", String(seconds)]
    process.standardInput = trigger
    try process.run()
    return (process, trigger)
  }
}
