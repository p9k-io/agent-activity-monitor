import AAMCore
import AAMPlatform
import Foundation

/// A fixed instant all synthetic fixtures are measured from.
let epoch = Date(timeIntervalSince1970: 1_800_000_000)

/// Treats every directory as its own Project, so adapter tests do not depend on git.
struct DirectoryIsProject: ProjectResolver {
  func project(for directory: String) -> Project {
    Project(root: directory)
  }
}

/// Open files as a test declares them, instead of asking the system.
struct DeclaredOpenFiles: OpenFileListing {
  var byPID: [Int32: [String]] = [:]

  func openFiles(of pid: Int32) -> [String] {
    byPID[pid] ?? []
  }
}

extension ProcessRecord {
  /// A synthetic process. Nothing here comes from a real machine.
  static func make(
    _ pid: Int32,
    parent: Int32 = 1,
    path: String,
    arguments: [String] = [],
    cwd: String? = "/work/alpha",
    terminal: Bool = true
  ) -> ProcessRecord {
    ProcessRecord(
      pid: pid,
      parentPID: parent,
      groupID: pid,
      userID: 501,
      startedAt: epoch,
      executablePath: path,
      arguments: arguments,
      workingDirectory: cwd,
      cpuTime: .zero,
      residentBytes: 0,
      isZombie: false,
      hasTerminal: terminal,
      markers: [:]
    )
  }
}

extension Snapshot {
  static func of(_ processes: ProcessRecord...) -> Snapshot {
    Snapshot(takenAt: epoch, processes: processes)
  }
}
