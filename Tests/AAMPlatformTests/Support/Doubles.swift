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

/// Open and mapped files as a test declares them, instead of asking the system.
struct DeclaredOpenFiles: OpenFileListing {
  var byPID: [Int32: [String]] = [:]
  var mapped: [Int32: [String]] = [:]

  func openFiles(of pid: Int32) -> [String] {
    byPID[pid] ?? []
  }

  func firstMappedFile(of pid: Int32, where matches: (String) -> Bool) -> String? {
    (mapped[pid] ?? []).first(where: matches)
  }
}

/// Counts how often a process is asked about, to show what a cache spares.
final class CountingFiles: OpenFileListing, @unchecked Sendable {
  private let lock = NSLock()
  private var asked = 0
  let open: [Int32: [String]]
  let mapped: [Int32: [String]]

  init(open: [Int32: [String]] = [:], mapped: [Int32: [String]] = [:]) {
    self.open = open
    self.mapped = mapped
  }

  /// How many times any process was asked about its open or mapped files.
  var timesAsked: Int {
    lock.withLock { asked }
  }

  func openFiles(of pid: Int32) -> [String] {
    lock.withLock { asked += 1 }
    return open[pid] ?? []
  }

  func firstMappedFile(of pid: Int32, where matches: (String) -> Bool) -> String? {
    lock.withLock { asked += 1 }
    return (mapped[pid] ?? []).first(where: matches)
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

/// Treats every process named `claude` as the root of a Session in its working directory.
struct ClaudeLike: HarnessAdapter {
  let harness = HarnessID.claudeCode
  let markerNames: Set<String> = []
  var state = SessionState.idle
  var lastActivityAt: Date?

  func sessions(in snapshot: Snapshot) -> [Session] {
    snapshot.processes.filter { $0.name == "claude" }.map { root in
      Session(
        id: SessionID(harness: harness, value: "s-\(root.pid)"), root: root.key,
        project: Project(root: root.workingDirectory ?? "/"),
        workingDirectory: root.workingDirectory ?? "/", title: nil, state: state,
        lastActivityAt: lastActivityAt, resumeCommand: nil, markers: [:])
    }
  }
}

/// Hands out prepared snapshots one after another and notes how each was asked for.
final class ScriptedSource: SamplingSource, @unchecked Sendable {
  private let lock = NSLock()
  private var remaining: [Snapshot]
  private var asked: [Bool] = []

  init(_ snapshots: [Snapshot]) {
    remaining = snapshots
  }

  /// Whether each snapshot so far was asked to refresh other users' processes.
  var refreshes: [Bool] {
    lock.withLock { asked }
  }

  func snapshot() -> Snapshot {
    snapshot(refreshingOtherUsers: true)
  }

  func snapshot(refreshingOtherUsers: Bool) -> Snapshot {
    lock.withLock {
      asked.append(refreshingOtherUsers)
      return remaining.count > 1 ? remaining.removeFirst() : remaining[0]
    }
  }
}
