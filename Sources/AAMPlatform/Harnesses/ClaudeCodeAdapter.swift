import AAMCore
import Foundation
import Synchronization

/// Finds Claude Code Sessions.
///
/// Claude Code keeps one small record per running process in `~/.claude/sessions/<pid>.json`.
/// The format is internal and undocumented: every field is read on its own, and anything that is
/// missing or has an unexpected type is treated as not known.
public final class ClaudeCodeAdapter: HarnessAdapter {
  public let harness = HarnessID.claudeCode
  public let markerNames: Set<String> = [ClaudeCodeAdapter.sessionMarker]

  private static let sessionMarker = "CLAUDE_CODE_SESSION_ID"

  /// What this adapter reads from a record.
  private struct Record: Sendable {
    let session: String?
    let directory: String?
    let name: String?
    let status: String?
    let statusChangedAt: Date?
  }

  private let records: URL
  private let projects: any ProjectResolver
  /// Records as last read, so that an unchanged file is not read and parsed on every look.
  private let known = Mutex<[Int32: (stamp: FileStamp, record: Record?)]>([:])

  public init(
    home: URL = FileManager.default.homeDirectoryForCurrentUser,
    projects: any ProjectResolver
  ) {
    records = home.appendingPathComponent(".claude/sessions", isDirectory: true)
    self.projects = projects
  }

  public func sessions(in snapshot: Snapshot) -> [Session] {
    snapshot.processes.filter(isClaudeCode).compactMap(session)
  }

  private func isClaudeCode(_ process: ProcessRecord) -> Bool {
    guard !process.isZombie else { return false }
    // The native install runs a file named after its version, started through a `claude` link.
    return process.executablePath.hasSuffix("/claude")
      || process.executablePath.contains("/claude/versions/")
      || process.arguments.first.map { $0 == "claude" || $0.hasSuffix("/claude") } == true
  }

  private func session(for process: ProcessRecord) -> Session? {
    let record = record(of: process.pid)
    // Without a record, only a process on a terminal can be a person's Session. Anything else
    // is one of Claude Code's helper modes.
    guard record != nil || process.hasTerminal else { return nil }

    let directory = record?.directory ?? process.workingDirectory ?? "/"
    return Session(
      id: SessionID(harness: harness, value: record?.session ?? "pid-\(process.pid)"),
      root: process.key,
      project: projects.project(for: directory),
      workingDirectory: directory,
      title: record?.name,
      state: state(record?.status),
      lastActivityAt: record?.statusChangedAt,
      resumeCommand: record?.session.map { "claude --resume \($0)" },
      markers: record?.session.map { [Self.sessionMarker: $0] } ?? [:]
    )
  }

  /// The record Claude Code wrote for this process, or nil when there is none, it cannot be
  /// read, or it was written for a different process.
  private func record(of pid: Int32) -> Record? {
    let file = records.appendingPathComponent("\(pid).json").path
    guard let stamp = FileStamp(path: file) else {
      known.withLock { $0[pid] = nil }
      return nil
    }
    if let cached = known.withLock({ $0[pid] }), cached.stamp == stamp {
      return cached.record
    }
    let record = read(file, for: pid)
    known.withLock { $0[pid] = (stamp, record) }
    return record
  }

  private func read(_ file: String, for pid: Int32) -> Record? {
    guard let data = FileManager.default.contents(atPath: file),
      let fields = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      fields["pid"] as? Int == Int(pid)
    else { return nil }
    let name = fields["name"] as? String
    let changed = (fields["statusUpdatedAt"] ?? fields["updatedAt"]) as? Double
    return Record(
      session: fields["sessionId"] as? String,
      directory: fields["cwd"] as? String,
      name: name?.isEmpty == false ? name : nil,
      status: fields["status"] as? String,
      statusChangedAt: changed.map { Date(timeIntervalSince1970: $0 / 1000) })
  }

  private func state(_ status: String?) -> SessionState {
    switch status {
    case "busy": .working
    case "waiting": .waiting
    case "shell": .background
    case "idle": .idle
    default: .unknown
    }
  }
}
