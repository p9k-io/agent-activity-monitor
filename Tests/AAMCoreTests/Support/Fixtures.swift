import AAMCore
import Foundation

/// A fixed instant all synthetic fixtures are measured from.
let epoch = Date(timeIntervalSince1970: 1_800_000_000)

extension ProcessRecord {
  /// A synthetic process. Nothing here comes from a real machine.
  static func make(
    _ pid: Int32,
    parent: Int32 = 1,
    path: String = "/usr/local/bin/tool",
    arguments: [String] = [],
    cwd: String? = nil,
    cpu: Duration = .zero,
    rss: UInt64 = 0,
    user: UInt32 = 501,
    startedAfter seconds: TimeInterval = 0,
    zombie: Bool = false,
    terminal: Bool = false,
    markers: [String: String] = [:]
  ) -> ProcessRecord {
    ProcessRecord(
      pid: pid,
      parentPID: parent,
      groupID: pid,
      userID: user,
      startedAt: epoch.addingTimeInterval(seconds),
      executablePath: path,
      arguments: arguments,
      workingDirectory: cwd,
      cpuTime: cpu,
      residentBytes: rss,
      isZombie: zombie,
      hasTerminal: terminal,
      markers: markers
    )
  }
}

extension Session {
  /// A synthetic Session rooted at `root`.
  static func make(
    _ value: String,
    root: ProcessRecord,
    harness: HarnessID = .claudeCode,
    project: String = "/work/alpha",
    title: String? = nil,
    state: SessionState = .idle,
    lastActivity: Date? = nil,
    resume: String? = nil,
    markers: [String: String] = [:]
  ) -> Session {
    Session(
      id: SessionID(harness: harness, value: value),
      root: root.key,
      project: Project(root: project),
      workingDirectory: project,
      title: title,
      state: state,
      lastActivityAt: lastActivity,
      resumeCommand: resume,
      markers: markers
    )
  }
}
