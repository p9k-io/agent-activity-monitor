import AAMCore
import Foundation
import Synchronization

/// Finds Codex CLI Sessions.
///
/// Codex appends every thread to a rollout file under `~/.codex/sessions` and keeps that file
/// open. The file name carries the thread identifier; the events inside tell whether a turn is
/// running. The format is internal and undocumented, so whatever cannot be read is not known.
public final class CodexAdapter: HarnessAdapter {
  public let harness = HarnessID.codex
  public let markerNames: Set<String> = []

  private let root: URL
  private let projects: any ProjectResolver
  private let openFiles: any OpenFileListing
  /// What each rollout said and how long it was then, so that only what was appended is read.
  private let rollouts = Mutex<[String: (size: Int64, tail: RolloutTail)]>([:])
  /// Thread names as last read from the index.
  private let titles = Mutex<(stamp: FileStamp?, names: [String: String])>((nil, [:]))

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
      let tail = thread?.path.map(tail(of:))
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
    return process.executablePath.hasSuffix("/codex")
      || process.arguments.first.map { $0 == "codex" || $0.hasSuffix("/codex") } == true
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

  /// What a rollout says now. A rollout only grows, so after the first read only the new end
  /// of the file is looked at.
  private func tail(of path: String) -> RolloutTail {
    guard let size = FileStamp(path: path)?.size else {
      rollouts.withLock { $0[path] = nil }
      return RolloutTail(path: path)
    }
    let known = rollouts.withLock { $0[path] }
    let tail: RolloutTail
    if let known, known.size == size {
      return known.tail
    } else if let known, known.size < size {
      tail = known.tail.advanced(path: path, from: UInt64(known.size), to: UInt64(size))
    } else {
      tail = RolloutTail(path: path)
    }
    rollouts.withLock { $0[path] = (size, tail) }
    return tail
  }

  /// Thread names from Codex's index, later lines winning. The index is read again only when
  /// it changes.
  private func threadTitles() -> [String: String] {
    let index = root.appendingPathComponent("session_index.jsonl").path
    let stamp = FileStamp(path: index)
    if let known = titles.withLock({ $0.stamp == stamp ? $0.names : nil }) {
      return known
    }
    var names: [String: String] = [:]
    if let data = FileManager.default.contents(atPath: index) {
      for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
        guard
          let entry = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
          let id = entry["id"] as? String,
          let name = entry["thread_name"] as? String,
          !name.isEmpty
        else { continue }
        names[id] = name
      }
    }
    titles.withLock { $0 = (stamp, names) }
    return names
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
