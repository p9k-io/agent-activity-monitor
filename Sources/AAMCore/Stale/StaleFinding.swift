import Foundation

/// How long things may sit before they count as Stale.
public struct StaleThresholds: Sendable, Equatable, Codable {
  /// A Session with no activity for this long is an Idle session.
  public var idleSession: Duration
  /// A dev server that used almost no CPU for this long, in a Session that is not working, is
  /// an Idle dev server.
  public var idleDevServer: Duration
  /// An Orphan is reported this long after its Session ended, so a Session that is still
  /// closing down is left alone.
  public var orphan: Duration
  /// Induced load is forgotten when nothing in its Project worked for this long.
  public var quietProject: Duration

  public init(
    idleSession: Duration = .seconds(24 * 3600),
    idleDevServer: Duration = .seconds(2 * 3600),
    orphan: Duration = .seconds(120),
    quietProject: Duration = .seconds(2 * 3600)
  ) {
    self.idleSession = idleSession
    self.idleDevServer = idleDevServer
    self.orphan = orphan
    self.quietProject = quietProject
  }
}

/// Something that is no longer needed: a candidate for Cleanup.
public struct StaleFinding: Sendable, Equatable, Identifiable {
  public enum Kind: String, Sendable, Codable, CaseIterable {
    case idleSession
    case ownerlessLeftover
    case forgottenInducedLoad
    case idleDevServer
  }

  /// Why the finding was made, with the facts a person needs to judge it.
  public enum Reason: Sendable, Equatable {
    case sessionIdle(since: Date)
    /// The Session and the time it ended are nil when nobody saw that Session.
    case orphan(formerSession: SessionID?, since: Date?)
    /// A zombie stays until its parent collects it or ends.
    case zombie(parent: Int32)
    /// An older copy of a server of which a newer copy runs in the same Session.
    case olderDuplicate(of: Int32)
    case projectQuiet(since: Date)
    case serverIdle(since: Date)
  }

  public let kind: Kind
  public let reason: Reason
  public let title: String
  public let project: Project
  public let session: SessionID?
  /// What a Cleanup of this finding would end.
  public let processes: [ProcessRecord.Key]
  /// The memory a Cleanup would free.
  public let residentBytes: UInt64
  /// False for what a Cleanup cannot end, such as a zombie.
  public let canCleanUp: Bool

  public init(
    kind: Kind,
    reason: Reason,
    title: String,
    project: Project,
    session: SessionID?,
    processes: [ProcessRecord.Key],
    residentBytes: UInt64,
    canCleanUp: Bool = true
  ) {
    self.kind = kind
    self.reason = reason
    self.title = title
    self.project = project
    self.session = session
    self.processes = processes
    self.residentBytes = residentBytes
    self.canCleanUp = canCleanUp
  }

  public var id: String {
    "\(kind.rawValue):\(processes.first.map { String($0.pid) } ?? title)"
  }
}
