/// Processes that run because of work done somewhere else and are counted and shown as one
/// thing: one simulator, the web content of one application.
public struct InducedLoad: Sendable, Equatable, Identifiable {
  public let id: String
  public let title: String
  public let processes: [ProcessRecord.Key]

  public init(id: String, title: String, processes: [ProcessRecord.Key]) {
    self.id = id
    self.title = title
    self.processes = processes
  }
}

/// Finds one kind of induced load among the processes of a snapshot.
public protocol InducedLoadLinker: Sendable {
  func inducedLoad(in snapshot: Snapshot) -> [InducedLoad]
}
