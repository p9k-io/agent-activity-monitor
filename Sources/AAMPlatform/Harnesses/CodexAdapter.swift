import AAMCore
import Foundation

/// Finds Codex CLI Sessions.
///
/// Codex appends every thread to a rollout file under `~/.codex/sessions` and keeps that file
/// open. The file name carries the thread identifier; the events inside tell whether a turn is
/// running. The format is internal and undocumented, so whatever cannot be read is not known.
public struct CodexAdapter: HarnessAdapter {
  public let harness = HarnessID.codex
  public let markerNames: Set<String> = []

  private let root: URL
  private let projects: any ProjectResolver
  private let openFiles: any OpenFileListing

  public init(
    home: URL = FileManager.default.homeDirectoryForCurrentUser,
    projects: any ProjectResolver,
    openFiles: any OpenFileListing = LibprocOpenFiles()
  ) {
    root = home.appendingPathComponent(".codex", isDirectory: true)
    self.projects = projects
    self.openFiles = openFiles
  }

  public func sessions(in snapshot: Snapshot) -> [Session] {
    let candidates = snapshot.processes.filter(isCodex)
    guard !candidates.isEmpty else { return [] }
    let tree = ProcessTree(snapshot.processes)
    let candidatePIDs = Set(candidates.map(\.pid))
    let titles = threadTitles()

    return candidates.compactMap { process in
      let thread = thread(of: process)
      if thread == nil {
        // Without a thread, only a process on a terminal can be a person's Session, and one
        // started by another Codex process is that Session's helper.
        let isHelper = tree.ancestors(of: process.pid).contains { candidatePIDs.contains($0.pid) }
        guard process.hasTerminal, !isHelper else { return nil }
      }
      let tail = thread?.path.map(RolloutTail.init(path:))
      let directory = process.workingDirectory ?? "/"
      return Session(
        id: SessionID(harness: harness, value: thread?.id ?? "pid-\(process.pid)"),
        root: process.key,
        project: projects.project(for: directory),
        workingDirectory: directory,
        title: thread.flatMap { titles[$0.id] },
        state: tail?.state ?? .unknown,
        lastActivityAt: tail?.lastActivityAt,
        resumeCommand: thread.map { "codex resume \($0.id)" },
        markers: [:]
      )
    }
  }

  private func isCodex(_ process: ProcessRecord) -> Bool {
    guard !process.isZombie else { return false }
    return process.name == "codex"
      || process.arguments.first?.split(separator: "/").last == "codex"
  }

  private struct Thread {
    let id: String
    let path: String?
  }

  /// The thread a Codex process works on: the rollout it holds open, or the one it was asked to
  /// resume.
  private func thread(of process: ProcessRecord) -> Thread? {
    let open = openFiles.openFiles(of: process.pid).compactMap(Rollout.init(path:))
    // A Session also holds the rollouts of the helpers it spawned. Its own thread came first.
    if let own = open.min(by: { $0.startedAt < $1.startedAt }) {
      return Thread(id: own.thread, path: own.path)
    }
    guard let resume = process.arguments.firstIndex(of: "resume"),
      process.arguments.indices.contains(resume + 1),
      UUID(uuidString: process.arguments[resume + 1]) != nil
    else { return nil }
    let identifier = process.arguments[resume + 1]
    return Thread(id: identifier, path: rolloutOnDisk(for: identifier))
  }

  private func rolloutOnDisk(for thread: String) -> String? {
    let sessions = root.appendingPathComponent("sessions", isDirectory: true)
    guard let files = FileManager.default.enumerator(atPath: sessions.path) else { return nil }
    let suffix = "-\(thread).jsonl"
    for case let file as String in files where file.hasSuffix(suffix) {
      return sessions.appendingPathComponent(file).path
    }
    return nil
  }

  /// Thread names from Codex's index, later lines winning.
  private func threadTitles() -> [String: String] {
    let index = root.appendingPathComponent("session_index.jsonl")
    guard let text = try? String(contentsOf: index, encoding: .utf8) else { return [:] }
    var titles: [String: String] = [:]
    for line in text.split(separator: "\n") {
      guard let entry = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
        let id = entry["id"] as? String,
        let name = entry["thread_name"] as? String,
        !name.isEmpty
      else { continue }
      titles[id] = name
    }
    return titles
  }
}

/// A rollout file, recognised by its name: `rollout-<start time>-<thread identifier>.jsonl`.
private struct Rollout {
  let path: String
  let startedAt: String
  let thread: String

  init?(path: String) {
    guard let name = path.split(separator: "/").last,
      name.hasPrefix("rollout-"), name.hasSuffix(".jsonl")
    else { return nil }
    let stem = name.dropFirst("rollout-".count).dropLast(".jsonl".count)
    // The thread identifier is a UUID: the last 36 characters, after one more hyphen.
    guard stem.count > 37 else { return nil }
    let thread = String(stem.suffix(36))
    guard UUID(uuidString: thread) != nil else { return nil }
    self.path = path
    self.thread = thread
    startedAt = String(stem.dropLast(37))
  }
}
