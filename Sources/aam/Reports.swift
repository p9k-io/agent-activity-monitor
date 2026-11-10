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
  /// The application the Session's terminal runs in, when that can be told. Where in it is
  /// left out: a panel's title can be anything.
  let host: String?

  init(_ group: SessionInventory, host: String? = nil) {
    let session = group.session
    self.host = host
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

  init(_ observation: Reading) {
    takenAt = observation.snapshot.takenAt
    sessions = observation.inventory.projects.flatMap(\.sessions).map {
      SessionRow($0, host: observation.places[$0.id]?.host)
    }
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

  init(_ observation: Reading, includeUnattributed: Bool) {
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

struct FindingRow: Encodable {
  struct Reason: Encodable {
    let kind: String
    let since: Date?
    let session: String?
    let pid: Int32?
  }

  let kind: String
  let reason: Reason
  let title: String
  let project: String
  let projectRoot: String
  let session: String?
  let pids: [Int32]
  let residentBytes: UInt64
  let canCleanUp: Bool
  /// The kind and the reason in words, as the app shows them.
  let kindLabel: String
  let reasonText: String

  init(_ finding: StaleFinding, now: Date) {
    kindLabel = finding.kind.label
    reasonText = finding.reason.text(now: now)
    kind = finding.kind.rawValue
    reason =
      switch finding.reason {
      case .sessionIdle(let since):
        Reason(kind: "sessionIdle", since: since, session: nil, pid: nil)
      case .orphan(let former, let since):
        Reason(kind: "orphan", since: since, session: former?.description, pid: nil)
      case .zombie(let parent):
        Reason(kind: "zombie", since: nil, session: nil, pid: parent)
      case .olderDuplicate(let newest):
        Reason(kind: "olderDuplicate", since: nil, session: nil, pid: newest)
      case .projectQuiet(let since):
        Reason(kind: "projectQuiet", since: since, session: nil, pid: nil)
      case .serverIdle(let since):
        Reason(kind: "serverIdle", since: since, session: nil, pid: nil)
      }
    title = finding.title
    project = finding.project.name
    projectRoot = finding.project.root
    session = finding.session?.description
    pids = finding.processes.map(\.pid)
    residentBytes = finding.residentBytes
    canCleanUp = finding.canCleanUp
  }
}

struct StaleReport: Encodable {
  let takenAt: Date
  /// The memory a Cleanup of everything that can be cleaned up would free.
  let reclaimableBytes: UInt64
  /// Whether CPU use is being watched over time, which judging dev servers needs.
  let activityObserved: Bool
  let findings: [FindingRow]

  init(takenAt: Date, findings: [StaleFinding], memory: Memory) {
    self.takenAt = takenAt
    reclaimableBytes = findings.filter(\.canCleanUp).reduce(0) { $0 + $1.residentBytes }
    activityObserved =
      memory.activityAsOf.map { takenAt.timeIntervalSince($0) <= Memory.longestActivityGap }
      ?? false
    self.findings = findings.map { FindingRow($0, now: takenAt) }
  }
}

struct RequestRow: Encodable {
  struct Refused: Encodable {
    let pid: Int32
    let reason: String
  }

  let id: String
  let createdAt: Date
  let requester: String?
  let reason: String
  let pids: [Int32]
  let status: String
  let decidedAt: Date?
  let outcome: CleanupRequest.Outcome?
  /// Processes that were asked for and left out, when the request was filed just now.
  let refused: [Refused]

  init(_ request: CleanupRequest, refused: [CleanupPlan.Refusal]) {
    id = request.id
    createdAt = request.createdAt
    requester = request.requester?.description
    reason = request.reason
    pids = request.targets.map(\.pid)
    status = request.status.rawValue
    decidedAt = request.decidedAt
    outcome = request.outcome
    self.refused = refused.map { Refused(pid: $0.process.pid, reason: $0.reason.rawValue) }
  }
}

struct RequestsReport: Encodable {
  let requests: [RequestRow]
}

func printJSON(_ value: some Encodable) throws {
  let encoder = JSONEncoder()
  encoder.dateEncodingStrategy = .iso8601
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
  print(String(decoding: try encoder.encode(value), as: UTF8.self))
}
