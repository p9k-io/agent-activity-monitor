import Foundation

/// Decides what in an Inventory is Stale.
///
/// A rule fires only on facts: a state the Harness reported, a time something was observed. What
/// is not known is not judged.
public struct StalenessRules: Sendable {
  public var thresholds: StaleThresholds

  public init(thresholds: StaleThresholds = StaleThresholds()) {
    self.thresholds = thresholds
  }

  public func findings(in inventory: Inventory, memory: Memory, now: Date) -> [StaleFinding] {
    let pass = Pass(thresholds: thresholds, memory: memory, now: now, tree: inventory.tree)
    var findings: [StaleFinding] = []
    for project in inventory.projects {
      for group in project.sessions {
        if let idle = pass.idleSession(group) {
          // Cleaning up the Session covers everything inside it.
          findings.append(idle)
        } else {
          findings += pass.zombies(in: group)
          findings += pass.olderDuplicates(in: group)
          findings += pass.idleDevServers(in: group)
        }
      }
      findings += pass.looseFindings(in: project)
    }
    return findings.sorted {
      ($1.residentBytes, $0.processes.first?.pid ?? 0)
        < ($0.residentBytes, $1.processes.first?.pid ?? 0)
    }
  }
}

extension Inventory {
  /// The parent and child links between every process of the Inventory.
  var tree: ProcessTree {
    var processes = unattributed
    for project in projects {
      processes += project.loose.map(\.process)
      processes += project.sessions.flatMap { $0.processes.map(\.process) }
    }
    return ProcessTree(processes)
  }
}

/// One run of the rules over an Inventory.
private struct Pass {
  let thresholds: StaleThresholds
  let memory: Memory
  let now: Date
  let tree: ProcessTree

  private static let inducedKinds: Set<ProcessKind> = [
    .simulator, .browserContent, .virtualMachine,
  ]
  private static let restingStates: Set<SessionState> = [.idle, .waiting, .background]

  // MARK: Sessions

  func idleSession(_ group: SessionInventory) -> StaleFinding? {
    let session = group.session
    guard Self.restingStates.contains(session.state), let since = session.lastActivityAt,
      hasPassed(thresholds.idleSession, since: since)
    else { return nil }
    return finding(
      .idleSession, .sessionIdle(since: since),
      title: session.title ?? session.project.name,
      project: session.project, session: session.id, group.processes.map(\.process))
  }

  func zombies(in group: SessionInventory) -> [StaleFinding] {
    group.processes.filter(\.process.isZombie).map { zombie in
      finding(
        .ownerlessLeftover, .zombie(parent: zombie.process.parentPID),
        title: zombie.process.name, project: group.session.project, session: group.session.id,
        [zombie.process], canCleanUp: false)
    }
  }

  /// An MCP server that was started again leaves its earlier copies running.
  func olderDuplicates(in group: SessionInventory) -> [StaleFinding] {
    let servers = group.processes.filter { $0.kind == .mcpServer && !$0.process.isZombie }
    let members = Set(group.processes.map(\.process.pid))
    return Dictionary(grouping: servers.map(\.process), by: Signature.init)
      .values
      .compactMap { copies -> StaleFinding? in
        let ordered = copies.sorted { ($0.startedAt, $0.pid) < ($1.startedAt, $1.pid) }
        guard let newest = ordered.last, ordered.count > 1 else { return nil }
        let older = ordered.dropLast().flatMap { subtree(of: $0, within: members) }
        return finding(
          .ownerlessLeftover, .olderDuplicate(of: newest.pid),
          title: newest.name, project: group.session.project, session: group.session.id, older)
      }
  }

  func idleDevServers(in group: SessionInventory) -> [StaleFinding] {
    guard Self.restingStates.contains(group.session.state) else { return [] }
    let members = Set(group.processes.map(\.process.pid))
    return devServerRoots(among: group.processes).compactMap { server in
      idleDevServer(
        server, within: members, project: group.session.project, session: group.session.id)
    }
  }

  // MARK: Loose processes

  func looseFindings(in project: ProjectInventory) -> [StaleFinding] {
    let members = Set(project.loose.map(\.process.pid))
    let servers = devServerRoots(among: project.loose)
    let serverTrees = Set(servers.flatMap { subtree(of: $0, within: members).map(\.pid) })
    let quietSince = quietSince(project)
    let isQuiet = quietSince.map { hasPassed(thresholds.quietProject, since: $0) } ?? false

    var findings: [StaleFinding] = []
    // A dev server is judged by whether anything still uses it, Orphan or not.
    for server in servers {
      let attributed = project.loose.first { $0.process.pid == server.pid }
      guard attributed?.isOrphan == true || isQuiet || project.sessions.isEmpty else { continue }
      if let idle = idleDevServer(server, within: members, project: project.project, session: nil) {
        findings.append(idle)
      }
    }

    let orphans = project.loose.filter { $0.isOrphan && !serverTrees.contains($0.process.pid) }
    for (former, group) in Dictionary(grouping: orphans, by: \.formerSession) {
      let since = former.flatMap { memory.sessions[$0]?.endedAt }
      let youngest = group.map(\.process.startedAt).max() ?? now
      guard hasPassed(thresholds.orphan, since: since ?? youngest) else { continue }
      findings.append(
        finding(
          .ownerlessLeftover, .orphan(formerSession: former, since: since),
          title: "Left behind in \(project.project.name)",
          project: project.project, session: nil, group.map(\.process)))
    }

    if isQuiet, let quietSince {
      let induced = project.loose.filter {
        !$0.isOrphan && Self.inducedKinds.contains($0.kind)
          && !members.contains($0.process.parentPID)
      }
      for root in induced {
        findings.append(
          finding(
            .forgottenInducedLoad, .projectQuiet(since: quietSince),
            title: root.process.name, project: project.project, session: nil,
            subtree(of: root.process, within: members)))
      }
    }
    return findings
  }

  /// Since when nothing in the Project has worked, or nil when something works now or the time
  /// is not known.
  private func quietSince(_ project: ProjectInventory) -> Date? {
    if project.sessions.contains(where: { !Self.restingStates.contains($0.session.state) }) {
      return nil
    }
    let live = project.sessions.compactMap(\.session.lastActivityAt)
    guard live.count == project.sessions.count else { return nil }
    let past = memory.sessions.values
      .filter { $0.project == project.project }
      .compactMap(\.endedAt)
    return (live + past).max()
  }

  // MARK: Dev servers

  /// Dev servers that are not started by another dev server among `processes`.
  private func devServerRoots(among processes: [AttributedProcess]) -> [ProcessRecord] {
    let servers = Set(processes.filter { $0.kind == .devServer }.map(\.process.pid))
    return processes.map(\.process).filter { process in
      servers.contains(process.pid)
        && !tree.ancestors(of: process.pid).contains { servers.contains($0.pid) }
    }
  }

  private func idleDevServer(
    _ server: ProcessRecord, within members: Set<Int32>, project: Project, session: SessionID?
  ) -> StaleFinding? {
    // A server whose activity was never observed, or is no longer being observed, is not judged.
    guard memory.lastBusyAt[server.key] != nil, let measured = memory.activityAsOf,
      now.timeIntervalSince(measured) <= Memory.longestActivityGap
    else { return nil }
    let processes = subtree(of: server, within: members)
    guard let since = processes.compactMap({ memory.lastBusyAt[$0.key] }).max(),
      hasPassed(thresholds.idleDevServer, since: since)
    else { return nil }
    return finding(
      .idleDevServer, .serverIdle(since: since),
      title: server.name, project: project, session: session, processes)
  }

  // MARK: Helpers

  private func hasPassed(_ duration: Duration, since date: Date) -> Bool {
    now.timeIntervalSince(date) >= duration.seconds
  }

  /// The process and what it started, as far as that is among `members`, by identifier.
  private func subtree(of process: ProcessRecord, within members: Set<Int32>) -> [ProcessRecord] {
    ([process] + tree.descendants(of: process.pid).filter { members.contains($0.pid) })
      .sorted { $0.pid < $1.pid }
  }

  private func finding(
    _ kind: StaleFinding.Kind, _ reason: StaleFinding.Reason, title: String, project: Project,
    session: SessionID?, _ processes: [ProcessRecord], canCleanUp: Bool = true
  ) -> StaleFinding {
    StaleFinding(
      kind: kind, reason: reason, title: title, project: project, session: session,
      processes: processes.map(\.key),
      residentBytes: processes.reduce(0) { $0 + $1.residentBytes },
      canCleanUp: canCleanUp)
  }
}

/// What makes two processes copies of the same server.
private struct Signature: Hashable {
  let parent: Int32
  let path: String
  let arguments: [String]

  init(_ process: ProcessRecord) {
    parent = process.parentPID
    path = process.executablePath
    arguments = process.arguments
  }
}
