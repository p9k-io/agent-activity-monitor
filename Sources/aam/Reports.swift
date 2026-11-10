import AAMCore
import Foundation

// The shapes `aam --json` prints. Command lines and environment values are never part of them.

struct SessionRow: Encodable {
  let id: String
  let harness: String
  let project: String
  let projectRoot: String
  let workingDirectory: String
  let title: String?
  let state: String
  let lastActivityAt: Date?
  let rootPID: Int32
  let processCount: Int
  let residentBytes: UInt64
  let resumeCommand: String?

  init(_ group: SessionInventory) {
    let session = group.session
    id = session.id.description
    harness = session.id.harness.rawValue
    project = session.project.name
    projectRoot = session.project.root
    workingDirectory = session.workingDirectory
    title = session.title
    state = session.state.rawValue
    lastActivityAt = session.lastActivityAt
    rootPID = session.root.pid
    processCount = group.processes.count
    residentBytes = group.residentBytes
    resumeCommand = session.resumeCommand
  }
}

struct ProcessRow: Encodable {
  let pid: Int32
  let parentPID: Int32
  let name: String
  let executablePath: String
  let evidence: String?
  let residentBytes: UInt64
  let isZombie: Bool
  let startedAt: Date

  init(_ process: ProcessRecord, evidence: Evidence?) {
    pid = process.pid
    parentPID = process.parentPID
    name = process.name
    executablePath = process.executablePath
    self.evidence = evidence?.rawValue
    residentBytes = process.residentBytes
    isZombie = process.isZombie
    startedAt = process.startedAt
  }
}

struct SessionsReport: Encodable {
  let takenAt: Date
  let sessions: [SessionRow]

  init(_ observation: Observation) {
    takenAt = observation.snapshot.takenAt
    sessions = observation.inventory.projects.flatMap(\.sessions).map(SessionRow.init)
  }
}

struct SessionDetail: Encodable {
  let session: SessionRow
  let processes: [ProcessRow]

  init(_ group: SessionInventory) {
    session = SessionRow(group)
    processes = group.processes.map { ProcessRow($0.process, evidence: $0.evidence) }
  }
}

struct ProjectRow: Encodable {
  let name: String
  let root: String
  let sessions: [SessionDetail]
}

struct ProcessesReport: Encodable {
  let takenAt: Date
  let projects: [ProjectRow]
  let unattributedCount: Int
  let unattributed: [ProcessRow]?

  init(_ observation: Observation, includeUnattributed: Bool) {
    takenAt = observation.snapshot.takenAt
    projects = observation.inventory.projects.map { project in
      ProjectRow(
        name: project.project.name,
        root: project.project.root,
        sessions: project.sessions.map(SessionDetail.init))
    }
    unattributedCount = observation.inventory.unattributed.count
    unattributed =
      includeUnattributed
      ? observation.inventory.unattributed.map { ProcessRow($0, evidence: nil) } : nil
  }
}

struct CulpritRow: Encodable {
  struct Owner: Encodable {
    let kind: String
    let session: String?
    let project: String?
  }

  let title: String
  let owner: Owner
  let cpuPercent: Double
  let residentBytes: UInt64
  let pids: [Int32]

  init(_ culprit: Culprit) {
    title = culprit.title
    owner =
      switch culprit.owner {
      case .session(let id, let project):
        Owner(kind: "session", session: id.description, project: project.root)
      case .project(let project):
        Owner(kind: "project", session: nil, project: project.root)
      case .none:
        Owner(kind: "none", session: nil, project: nil)
      }
    cpuPercent = (culprit.cpuPercent * 10).rounded() / 10
    residentBytes = culprit.residentBytes
    pids = culprit.processes.map(\.pid)
  }
}

struct CulpritsReport: Encodable {
  let takenAt: Date
  let intervalSeconds: Double
  let culprits: [CulpritRow]

  init(takenAt: Date, intervalSeconds: Double, culprits: [Culprit]) {
    self.takenAt = takenAt
    self.intervalSeconds = intervalSeconds
    self.culprits = culprits.map(CulpritRow.init)
  }
}

struct MineReport: Encodable {
  let takenAt: Date
  let session: SessionRow
  let processes: [ProcessRow]

  init(takenAt: Date, group: SessionInventory) {
    self.takenAt = takenAt
    session = SessionRow(group)
    processes = group.processes.map { ProcessRow($0.process, evidence: $0.evidence) }
  }
}

func printJSON(_ value: some Encodable) throws {
  let encoder = JSONEncoder()
  encoder.dateEncodingStrategy = .iso8601
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
  print(String(decoding: try encoder.encode(value), as: UTF8.self))
}
