import AAMCore
import Foundation

/// Finds Claude Code Sessions.
///
/// Claude Code keeps one small record per running process in `~/.claude/sessions/<pid>.json`.
/// The format is internal and undocumented: every field is read on its own, and anything that is
/// missing or has an unexpected type is treated as not known.
public struct ClaudeCodeAdapter: HarnessAdapter {
  public let harness = HarnessID.claudeCode
  public let markerNames: Set<String> = [ClaudeCodeAdapter.sessionMarker]

  private static let sessionMarker = "CLAUDE_CODE_SESSION_ID"

  private let records: URL
  private let projects: any ProjectResolver

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
    return process.name == "claude"
      || process.executablePath.contains("/claude/versions/")
      || process.arguments.first?.split(separator: "/").last == "claude"
  }

  private func session(for process: ProcessRecord) -> Session? {
    let record = record(of: process.pid)
    // Without a record, only a process on a terminal can be a person's Session. Anything else
    // is one of Claude Code's helper modes.
    guard record != nil || process.hasTerminal else { return nil }

    let identifier = record?["sessionId"] as? String
    let directory = record?["cwd"] as? String ?? process.workingDirectory ?? "/"
    let title = record?["name"] as? String
    return Session(
      id: SessionID(harness: harness, value: identifier ?? "pid-\(process.pid)"),
      root: process.key,
      project: projects.project(for: directory),
      workingDirectory: directory,
      title: title?.isEmpty == false ? title : nil,
      state: state(record?["status"] as? String),
      lastActivityAt: date(milliseconds: record?["statusUpdatedAt"] ?? record?["updatedAt"]),
      resumeCommand: identifier.map { "claude --resume \($0)" },
      markers: identifier.map { [Self.sessionMarker: $0] } ?? [:]
    )
  }

  /// The record Claude Code wrote for this process, or nil when there is none, it cannot be
  /// read, or it was written for a different process.
  private func record(of pid: Int32) -> [String: Any]? {
    let file = records.appendingPathComponent("\(pid).json")
    guard let data = try? Data(contentsOf: file),
      let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      record["pid"] as? Int == Int(pid)
    else { return nil }
    return record
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

  private func date(milliseconds value: Any?) -> Date? {
    (value as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
  }
}
