import Foundation

/// Shuts a simulator down the way Xcode's own tool does, instead of ending its processes.
public struct SimulatorControl: Sendable {
  private let run: @Sendable ([String]) -> Int32

  /// - Parameter run: Runs `xcrun` with the given arguments and returns its exit status.
  public init(run: @escaping @Sendable ([String]) -> Int32 = SimulatorControl.xcrun) {
    self.run = run
  }

  /// Whether the simulator was shut down. Anything but a device identifier is refused.
  public func shutDown(device: String) -> Bool {
    guard UUID(uuidString: device) != nil else { return false }
    return run(["simctl", "shutdown", device]) == 0
  }

  public static func xcrun(_ arguments: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
    } catch {
      return -1
    }
    process.waitUntilExit()
    return process.terminationStatus
  }
}
