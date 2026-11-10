import Foundation

/// Why an Attribution holds.
public enum Evidence: String, Sendable, Codable, CaseIterable {
  /// The process is the Session's root or one of its descendants.
  case tree
  /// The process carries the Session's marker in its environment.
  case tagged
  /// The process was seen in the Session tree earlier.
  case remembered
  /// The working directory or the timing points to the Project.
  case inferred
}

/// A process together with the reason it is counted where it is.
public struct AttributedProcess: Sendable, Equatable, Identifiable {
  public let process: ProcessRecord
  public let evidence: Evidence

  public init(process: ProcessRecord, evidence: Evidence) {
    self.process = process
    self.evidence = evidence
  }

  public var id: ProcessRecord.Key { process.key }
}

/// A Session and the processes attributed to it. The root process comes first.
public struct SessionInventory: Sendable, Equatable, Identifiable {
  public let session: Session
  public let processes: [AttributedProcess]

  public init(session: Session, processes: [AttributedProcess]) {
    self.session = session
    self.processes = processes
  }

  public var id: SessionID { session.id }
}

/// A Project, its Sessions, and the processes that belong to the Project but to no single Session.
public struct ProjectInventory: Sendable, Equatable, Identifiable {
  public let project: Project
  public let sessions: [SessionInventory]
  public let loose: [AttributedProcess]

  public init(project: Project, sessions: [SessionInventory], loose: [AttributedProcess]) {
    self.project = project
    self.sessions = sessions
    self.loose = loose
  }

  public var id: String { project.id }
}

/// Every process of one snapshot, sorted into Projects and Sessions.
public struct Inventory: Sendable, Equatable {
  public let takenAt: Date
  public let projects: [ProjectInventory]
  public let unattributed: [ProcessRecord]

  public init(takenAt: Date, projects: [ProjectInventory], unattributed: [ProcessRecord]) {
    self.takenAt = takenAt
    self.projects = projects
    self.unattributed = unattributed
  }
}
