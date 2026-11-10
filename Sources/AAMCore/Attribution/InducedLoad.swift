/// Processes that run because of work done somewhere else and are counted and shown as one
/// thing: one simulator, the web content of one application.
public struct InducedLoad: Sendable, Equatable, Identifiable {
  /// What the load is. It decides whether and how the load can be cleaned up.
  public enum Kind: Sendable, Hashable {
    /// A booted simulator, with the identifier of its device when that can be told.
    case simulator(device: String?)
    /// The pages of one application, by the application's identifier.
    case webContent(application: String)
    case virtualMachine
  }

  public let id: String
  public let kind: Kind
  public let title: String
  public let processes: [ProcessRecord.Key]

  public init(id: String, kind: Kind, title: String, processes: [ProcessRecord.Key]) {
    self.id = id
    self.kind = kind
    self.title = title
    self.processes = processes
  }
}

/// Finds one kind of induced load among the processes of a snapshot.
public protocol InducedLoadLinker: Sendable {
  func inducedLoad(in snapshot: Snapshot) -> [InducedLoad]
}
