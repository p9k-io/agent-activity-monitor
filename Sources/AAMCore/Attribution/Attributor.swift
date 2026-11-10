/// Sorts the processes of a snapshot into Projects and Sessions.
///
/// Evidence is tried from the strongest: the Session tree, the Session's marker, what Memory
/// holds, and last the working directory of a daemon. A process without Evidence stays
/// unattributed. The Attributor never guesses.
public struct Attributor: Sendable {
  private let classifier: ProcessClassifier
  private let projects: any ProjectResolver

  /// - Parameter projects: Decides the Project of a marked process whose Session nobody saw.
  public init(
    classifier: ProcessClassifier = .standard,
    projects: any ProjectResolver = DirectoryAsProject()
  ) {
    self.classifier = classifier
    self.projects = projects
  }

  public func inventory(
    of snapshot: Snapshot,
    sessions: [Session],
    memory: Memory = .empty
  ) -> Inventory {
    let tree = ProcessTree(snapshot.processes)
    // A Session whose root is gone, or whose identifier now belongs to another process, is over.
    let live = sessions.filter { tree.process($0.root.pid)?.key == $0.root }
    var sorter = Sorter(live: live, memory: memory, tree: tree, classifier: classifier)

    var pending: [ProcessRecord] = []
    for process in snapshot.processes where !sorter.attribute(process, projects: projects) {
      pending.append(process)
    }
    // What a loose process started belongs where the loose process belongs.
    let unattributed = pending.filter { !sorter.inherit($0) }

    return Inventory(
      takenAt: snapshot.takenAt,
      projects: sorter.projectInventories(),
      unattributed: unattributed
    )
  }
}

/// The Project of a directory is the directory itself. Used where no resolver is given.
public struct DirectoryAsProject: ProjectResolver {
  public init() {}

  public func project(for directory: String) -> Project {
    Project(root: directory)
  }
}

/// The working state of one attribution pass.
private struct Sorter {
  let live: [Session]
  let memory: Memory
  let tree: ProcessTree
  let classifier: ProcessClassifier

  private let liveByID: [SessionID: Session]
  private let ownerByRoot: [Int32: SessionID]
  private let liveByMarker: [Marker: SessionID]
  private let pastByMarker: [Marker: SessionID]
  /// Roots of the Projects that have or had Sessions, longest first.
  private let knownRoots: [String]

  private var owned: [SessionID: [AttributedProcess]] = [:]
  private var loose: [Project: [AttributedProcess]] = [:]
  private var looseByPID: [Int32: (project: Project, attributed: AttributedProcess)] = [:]

  init(live: [Session], memory: Memory, tree: ProcessTree, classifier: ProcessClassifier) {
    self.live = live
    self.memory = memory
    self.tree = tree
    self.classifier = classifier
    liveByID = Dictionary(live.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    ownerByRoot = Dictionary(
      live.map { ($0.root.pid, $0.id) }, uniquingKeysWith: { first, _ in first })

    var liveMarkers: [Marker: SessionID] = [:]
    for session in live {
      for (name, value) in session.markers {
        liveMarkers[Marker(name: name, value: value)] = session.id
      }
    }
    liveByMarker = liveMarkers

    var pastMarkers: [Marker: SessionID] = [:]
    for (id, session) in memory.sessions where liveByID[id] == nil {
      for (name, value) in session.markers {
        pastMarkers[Marker(name: name, value: value)] = id
      }
    }
    pastByMarker = pastMarkers

    let roots = Set(live.map(\.project.root)).union(memory.sessions.values.map(\.project.root))
    knownRoots = roots.sorted { $0.count > $1.count }
  }

  /// Attributes `process` when there is Evidence for it. Returns whether it was attributed.
  mutating func attribute(_ process: ProcessRecord, projects: any ProjectResolver) -> Bool {
    if let owner = treeOwner(of: process) {
      own(process, by: owner, evidence: .tree)
    } else if let owner = marker(of: process, in: liveByMarker) {
      own(process, by: owner, evidence: .tagged)
    } else if let lineage = memory.lineage[process.key] {
      if liveByID[lineage.session] != nil {
        own(process, by: lineage.session, evidence: .remembered)
      } else {
        orphan(process, in: lineage.project, evidence: .remembered, from: lineage.session)
      }
    } else if let former = marker(of: process, in: pastByMarker),
      let project = memory.sessions[former]?.project
    {
      orphan(process, in: project, evidence: .tagged, from: former)
    } else if !process.markers.isEmpty, let directory = process.workingDirectory {
      // Marked by a Session that ended before anyone looked.
      let project = knownProject(containing: directory) ?? projects.project(for: directory)
      orphan(process, in: project, evidence: .tagged, from: nil)
    } else if let project = inferredProject(of: process) {
      place(
        AttributedProcess(process: process, evidence: .inferred, kind: kind(of: process)),
        in: project)
    } else {
      return false
    }
    return true
  }

  /// Gives `process` the place of the nearest loose process above it, if there is one.
  mutating func inherit(_ process: ProcessRecord) -> Bool {
    for ancestor in tree.ancestors(of: process.pid) {
      guard let found = looseByPID[ancestor.pid] else { continue }
      place(
        AttributedProcess(
          process: process,
          evidence: found.attributed.evidence,
          kind: kind(of: process),
          isOrphan: found.attributed.isOrphan,
          formerSession: found.attributed.formerSession),
        in: found.project)
      return true
    }
    return false
  }

  func projectInventories() -> [ProjectInventory] {
    let sessionsByProject = Dictionary(grouping: live, by: \.project)
    let all = Set(sessionsByProject.keys).union(loose.keys)
    return
      all
      .map { project in
        ProjectInventory(
          project: project,
          sessions: (sessionsByProject[project] ?? [])
            .sorted { ($0.root.startedAt, $0.id.value) < ($1.root.startedAt, $1.id.value) }
            .map { session in
              SessionInventory(
                session: session,
                processes: ordered(owned[session.id] ?? [], first: session.root.pid))
            },
          loose: ordered(loose[project] ?? [], first: nil)
        )
      }
      .sorted { ($0.project.name, $0.project.root) < ($1.project.name, $1.project.root) }
  }

  // MARK: Evidence

  /// The Session whose root is the process itself or its nearest ancestor.
  private func treeOwner(of process: ProcessRecord) -> SessionID? {
    if let owner = ownerByRoot[process.pid] { return owner }
    for ancestor in tree.ancestors(of: process.pid) {
      if let owner = ownerByRoot[ancestor.pid] { return owner }
    }
    return nil
  }

  private func marker(of process: ProcessRecord, in index: [Marker: SessionID]) -> SessionID? {
    for (name, value) in process.markers {
      if let owner = index[Marker(name: name, value: value)] { return owner }
    }
    return nil
  }

  /// A daemon belongs to a known Project when it runs inside it. A process on a terminal, or one
  /// that still has its parent, may be a person's own work and is left alone.
  private func inferredProject(of process: ProcessRecord) -> Project? {
    guard process.parentPID == 1, !process.hasTerminal, let directory = process.workingDirectory
    else { return nil }
    return knownProject(containing: directory)
  }

  private func knownProject(containing directory: String) -> Project? {
    knownRoots
      .first { directory == $0 || directory.hasPrefix($0 + "/") }
      .map(Project.init(root:))
  }

  // MARK: Placement

  private func kind(of process: ProcessRecord) -> ProcessKind {
    ownerByRoot[process.pid] != nil ? .harness : classifier.kind(of: process)
  }

  private mutating func own(_ process: ProcessRecord, by session: SessionID, evidence: Evidence) {
    owned[session, default: []].append(
      AttributedProcess(process: process, evidence: evidence, kind: kind(of: process)))
  }

  private mutating func orphan(
    _ process: ProcessRecord, in project: Project, evidence: Evidence, from session: SessionID?
  ) {
    place(
      AttributedProcess(
        process: process, evidence: evidence, kind: kind(of: process), isOrphan: true,
        formerSession: session),
      in: project)
  }

  private mutating func place(_ attributed: AttributedProcess, in project: Project) {
    loose[project, default: []].append(attributed)
    looseByPID[attributed.process.pid] = (project, attributed)
  }

  private func ordered(_ processes: [AttributedProcess], first root: Int32?) -> [AttributedProcess]
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
