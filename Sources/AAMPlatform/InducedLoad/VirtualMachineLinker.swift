import AAMCore

/// A virtual machine runs in a helper process started by the system. The disk image it has
/// open tells which tool it belongs to.
public final class VirtualMachineLinker: InducedLoadLinker {
  /// Text in the path of a disk image, and the tool it gives away.
  private static let tools: [(text: String, name: String)] = [
    ("com.docker.docker", "Docker"),
    ("/containers/podman/", "Podman"),
    ("/.colima/", "Colima"),
    ("/.lima/", "Lima"),
    ("/OrbStack/", "OrbStack"),
    ("/com.utmapp.UTM/", "UTM"),
  ]

  private let files: any OpenFileListing
  private let cache = OwnerCache()

  public init(files: any OpenFileListing = LibprocOpenFiles()) {
    self.files = files
  }

  public func inducedLoad(in snapshot: Snapshot) -> [InducedLoad] {
    let machines = snapshot.processes.filter {
      $0.name == "com.apple.Virtualization.VirtualMachine"
    }
    let tools = cache.owners(of: machines) { machine in
      files.firstFile(of: machine.pid) { Self.tool(in: $0) != nil }.flatMap(Self.tool)
    }
    return machines.map { machine in
      let tool = tools[machine.key] ?? nil
      return InducedLoad(
        id: "virtual-machine:\(machine.pid)",
        kind: .virtualMachine,
        title: tool.map { "Virtual machine of \($0)" } ?? "Virtual machine",
        processes: [machine.key])
    }
  }

  private static func tool(in path: String) -> String? {
    tools.first { path.contains($0.text) }?.name
  }
}
