import Darwin
import Foundation

/// Starts the test helper, a process these tests own and may end.
enum Helper {
  /// The helper is built next to the test bundle, which is found among the loaded images.
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
    return URL(fileURLWithPath: ".build/debug/aam-test-helper")
  }()

  /// Starts the helper in one of its modes: `sleep`, `ignore-term` or `tree`.
  static func start(_ mode: String, seconds: Int = 30) throws -> Process {
    let process = Process()
    process.executableURL = url
    process.arguments = [mode, String(seconds)]
    try process.run()
    return process
  }
}
