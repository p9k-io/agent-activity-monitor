/// What one look at the machine found.
///
/// Not called an observation: a type of that name would hide Swift's Observation module from
/// every client that imports this one.
public struct Reading: Sendable, Equatable {
  public let snapshot: Snapshot
  public let sessions: [Session]
  public let inventory: Inventory

  public init(snapshot: Snapshot, sessions: [Session], inventory: Inventory) {
    self.snapshot = snapshot
    self.sessions = sessions
    self.inventory = inventory
  }
}

/// Looks at the machine once: takes a snapshot, asks every Harness adapter for its Sessions and
/// sorts the processes into Projects and Sessions.
public struct Observer: Sendable {
  private let source: any ProcessSource
  private let adapters: [any HarnessAdapter]
  private let linkers: [any InducedLoadLinker]
  private let attributor: Attributor

  public init(
    source: any ProcessSource,
    adapters: [any HarnessAdapter],
    linkers: [any InducedLoadLinker] = [],
    projects: any ProjectResolver = DirectoryAsProject()
  ) {
    self.source = source
    self.adapters = adapters
    self.linkers = linkers
    attributor = Attributor(projects: projects)
  }

  /// - Parameter memory: What earlier looks found. It lets a process be attributed after the
  ///   process table no longer links it to its Session.
  public func observe(remembering memory: Memory = .empty) -> Reading {
    observe(source.snapshot(), remembering: memory)
  }

  /// Sorts a snapshot that was taken already.
  public func observe(_ snapshot: Snapshot, remembering memory: Memory = .empty) -> Reading {
    let sessions = adapters.flatMap { $0.sessions(in: snapshot) }
    return Reading(
      snapshot: snapshot,
      sessions: sessions,
      inventory: attributor.inventory(of: snapshot, sessions: sessions, memory: memory)
    )
  }

  /// The induced load among the processes of a snapshot. Finding it costs more than a look, so
  /// it is done only for whoever asks.
  public func inducedLoad(in snapshot: Snapshot) -> [InducedLoad] {
    linkers.flatMap { $0.inducedLoad(in: snapshot) }
  }
}

extension Inventory {
  /// The Session a process is attributed to, with everything else attributed to it.
  public func session(owning pid: Int32) -> SessionInventory? {
    for project in projects {
      for group in project.sessions
      where group.processes.contains(where: { $0.process.pid == pid }) {
        return group
      }
    }
    return nil
  }
}

extension SessionInventory {
  public var residentBytes: UInt64 {
    processes.reduce(0) { $0 + $1.process.residentBytes }
  }
}
