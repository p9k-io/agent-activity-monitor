import AAMCore
import Foundation

/// A booted simulator is one `launchd_sim` process with everything inside the device below it.
public struct SimulatorLinker: InducedLoadLinker {
  private let devices: URL

  /// - Parameter devices: Where CoreSimulator keeps one folder per device.
  public init(
    devices: URL = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Developer/CoreSimulator/Devices", isDirectory: true)
  ) {
    self.devices = devices
  }

  public func inducedLoad(in snapshot: Snapshot) -> [InducedLoad] {
    let roots = snapshot.processes.filter { $0.name == "launchd_sim" }
    guard !roots.isEmpty else { return [] }
    let tree = ProcessTree(snapshot.processes)
    return roots.map { root in
      let device = deviceIdentifier(of: root)
      return InducedLoad(
        id: "simulator:\(device ?? String(root.pid))",
        title: device.flatMap(deviceName).map { "iOS Simulator · \($0)" } ?? "iOS Simulator",
        processes: [root.key] + tree.descendants(of: root.pid).map(\.key))
    }
  }

  /// The device a simulator runs, read from the path it was started with.
  private func deviceIdentifier(of root: ProcessRecord) -> String? {
    for argument in root.arguments {
      let parts = argument.split(separator: "/")
      guard let folder = parts.firstIndex(of: "Devices"), parts.indices.contains(folder + 1)
      else { continue }
      let candidate = String(parts[folder + 1])
      if UUID(uuidString: candidate) != nil { return candidate }
    }
    return nil
  }

  private func deviceName(_ identifier: String) -> String? {
    let record = devices.appendingPathComponent(identifier).appendingPathComponent("device.plist")
    guard let data = try? Data(contentsOf: record),
      let fields = try? PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: Any]
    else { return nil }
    return fields["name"] as? String
  }
}
