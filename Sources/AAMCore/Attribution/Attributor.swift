/// Sorts the processes of a snapshot into Projects and Sessions.
///
/// A process without Evidence stays unattributed. The Attributor never guesses.
public struct Attributor: Sendable {
  public init() {}

  public func inventory(of snapshot: Snapshot, sessions: [Session]) -> Inventory {
    let tree = ProcessTree(snapshot.processes)
    // A Session whose root is gone, or whose identifier now belongs to another process, is over.
    let live = sessions.filter { tree.process($0.root.pid)?.key == $0.root }
    let ownerByRoot = Dictionary(
      live.map { ($0.root.pid, $0.id) }, uniquingKeysWith: { first, _ in first })
    let ownerByMarker = markerIndex(of: live)

    var owned: [SessionID: [AttributedProcess]] = [:]
    var unattributed: [ProcessRecord] = []
    for process in snapshot.processes {
      if let owner = treeOwner(of: process, in: tree, ownerByRoot) {
        owned[owner, default: []].append(AttributedProcess(process: process, evidence: .tree))
      } else if let owner = markerOwner(of: process, ownerByMarker) {
        owned[owner, default: []].append(AttributedProcess(process: process, evidence: .tagged))
      } else {
        unattributed.append(process)
      }
    }

    return Inventory(
      takenAt: snapshot.takenAt,
      projects: projects(of: live, owned: owned),
      unattributed: unattributed
    )
  }

  /// The Session whose root is the process itself or its nearest ancestor.
  private func treeOwner(
    of process: ProcessRecord,
    in tree: ProcessTree,
    _ ownerByRoot: [Int32: SessionID]
  ) -> SessionID? {
    if let owner = ownerByRoot[process.pid] { return owner }
    for ancestor in tree.ancestors(of: process.pid) {
      if let owner = ownerByRoot[ancestor.pid] { return owner }
    }
    return nil
  }

  private func markerIndex(of sessions: [Session]) -> [Marker: SessionID] {
    var index: [Marker: SessionID] = [:]
    for session in sessions {
      for (name, value) in session.markers {
        index[Marker(name: name, value: value)] = session.id
      }
    }
    return index
  }

  private func markerOwner(
    of process: ProcessRecord,
    _ ownerByMarker: [Marker: SessionID]
  ) -> SessionID? {
    for (name, value) in process.markers {
      if let owner = ownerByMarker[Marker(name: name, value: value)] { return owner }
    }
    return nil
  }

  private func projects(
    of sessions: [Session],
    owned: [SessionID: [AttributedProcess]]
  ) -> [ProjectInventory] {
    Dictionary(grouping: sessions, by: \.project)
      .map { project, sessions in
        ProjectInventory(
          project: project,
          sessions:
            sessions
            .sorted { ($0.root.startedAt, $0.id.value) < ($1.root.startedAt, $1.id.value) }
            .map { session in
              SessionInventory(
                session: session,
                processes: ordered(owned[session.id] ?? [], rootFirst: session.root.pid))
            },
          loose: []
        )
      }
      .sorted { ($0.project.name, $0.project.root) < ($1.project.name, $1.project.root) }
  }

  private func ordered(_ processes: [AttributedProcess], rootFirst root: Int32) -> [AttributedProcess]
  {
    processes.sorted { left, right in
      if left.process.pid == root { return true }
      if right.process.pid == root { return false }
      return left.process.pid < right.process.pid
    }
  }
}

private struct Marker: Hashable {
  let name: String
  let value: String
}
