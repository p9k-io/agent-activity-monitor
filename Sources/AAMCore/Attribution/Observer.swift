/// What one look at the machine found.
public struct Observation: Sendable, Equatable {
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
  private let attributor = Attributor()

  public init(source: any ProcessSource, adapters: [any HarnessAdapter]) {
    self.source = source
    self.adapters = adapters
  }

  public func observe() -> Observation {
    let snapshot = source.snapshot()
    let sessions = adapters.flatMap { $0.sessions(in: snapshot) }
    return Observation(
      snapshot: snapshot,
      sessions: sessions,
      inventory: attributor.inventory(of: snapshot, sessions: sessions)
    )
  }
}

extension Inventory {
  /// The Session a process is attributed to, with everything else attributed to it.
  public func session(owning pid: Int32) -> SessionInventory? {
    for project in projects {
      for group in project.sessions where group.processes.contains(where: { $0.process.pid == pid })
      {
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
