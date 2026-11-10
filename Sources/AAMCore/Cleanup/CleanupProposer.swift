import Foundation

/// Words a Cleanup as a proposal a person can judge, from what one look found.
///
/// Nothing is ended here. A proposal says what a Cleanup would do; carrying it out is up to the
/// app, after a person has confirmed it.
public struct CleanupProposer: Sendable {
  /// Where an attributed process belongs.
  private struct Place {
    let kind: ProcessKind
    let session: Session?
  }

  private let reading: Reading
  private let planner: CleanupPlanner
  private let places: [Int32: Place]

  public init(reading: Reading, planner: CleanupPlanner) {
    self.reading = reading
    self.planner = planner
    var places: [Int32: Place] = [:]
    for project in reading.inventory.projects {
      for group in project.sessions {
        for attributed in group.processes {
          places[attributed.process.pid] = Place(kind: attributed.kind, session: group.session)
        }
      }
      for attributed in project.loose {
        places[attributed.process.pid] = Place(kind: attributed.kind, session: nil)
      }
    }
    self.places = places
  }

  /// Ending a Session: everything attributed to it, with the command that reopens it.
  public func ending(_ id: SessionID) -> CleanupProposal? {
    guard let group = group(id) else { return nil }
    let session = group.session
    var message = "\(session.id.harness.label) in \(session.project.name)."
    if session.state != .working, let last = session.lastActivityAt {
      message += " Last active \(Format.span(from: last, to: now)) ago."
    }
    return proposal(
      id: "session:\(id)",
      title: "End the Session \(quoted(session.displayTitle))?",
      message: message,
      cautions: [stateCaution(session)].compactMap(\.self),
      asking: group.processes.map(\.process.key),
      resume: [resume(session)].compactMap(\.self))
  }

  /// Cleaning up Stale findings. Findings that cannot be cleaned up are left out, and with none
  /// left there is nothing to propose.
  public func cleaningUp(_ findings: [StaleFinding]) -> CleanupProposal? {
    let findings = findings.filter(\.canCleanUp)
    guard let first = findings.first else { return nil }
    // An Idle session is ended as a whole, so it is treated like any Session that is ended.
    let ended = findings.filter { $0.kind == .idleSession }
      .compactMap { $0.session.flatMap(group)?.session }
    let projects = Set(findings.map(\.project)).count
    return proposal(
      id: "findings:" + findings.map(\.id).joined(separator: ","),
      title: findings.count == 1
        ? "Clean up \(quoted(first.title))?" : "Clean up \(findings.count) findings?",
      message: findings.count == 1
        ? "\(first.kind.label) in \(first.project.name): \(first.reason.text(now: now))."
        : "In \(projects) \(projects == 1 ? "Project" : "Projects").",
      cautions: ended.compactMap(stateCaution) + findings.compactMap(duplicateCaution),
      asking: findings.flatMap(\.processes),
      resume: ended.compactMap(resume))
  }

  /// Ending what a Culprit is made of. Nil for a Culprit that can only be shown: a virtual
  /// machine, a simulator whose device is not known, or processes outside every Session.
  public func ending(_ culprit: Culprit) -> CleanupProposal? {
    if case .session(let id, _) = culprit.owner { return ending(id) }
    switch culprit.load {
    case .webContent:
      return proposal(
        id: "culprit:\(culprit.id)",
        title: "End \(quoted(culprit.title))?",
        message: "These processes show the pages of the application.",
        cautions: [
          "The pages go blank or load again, depending on the application. "
            + "What was typed into a page and not saved is lost."
        ],
        asking: culprit.processes)
    case .simulator(let device?):
      return proposal(
        id: "culprit:\(culprit.id)",
        title: "Shut down \(quoted(culprit.title))?",
        message: "The simulator is shut down the way Xcode does it. What runs in it ends with it.",
        means: .shutDownSimulator(device: device),
        asking: culprit.processes)
    case .simulator(nil), .virtualMachine, nil:
      return nil
    }
  }

  /// Approving a Cleanup request: its targets and what they started.
  public func answering(_ request: CleanupRequest) -> CleanupProposal {
    let plan = planner.plan(for: request.targets, in: reading.snapshot)
    var cautions: [String] = []
    var ended: [Session] = []
    var seen: Set<SessionID> = []
    for session in plan.targets.compactMap({ places[$0.pid]?.session })
    where seen.insert(session.id).inserted {
      let name = quoted(session.displayTitle)
      if plan.targets.contains(where: { $0.key == session.root }) {
        ended.append(session)
        cautions.append("This ends the whole Session \(name).")
        if let caution = stateCaution(session) { cautions.append(caution) }
      } else if session.id != request.requester {
        cautions.append(
          "Processes of the Session \(name) are among these, and it is not the one asking.")
      }
    }
    let nowhere = plan.targets.count { places[$0.pid] == nil }
    if nowhere > 0 {
      cautions.append(
        "\(nowhere) of these processes \(nowhere == 1 ? "belongs" : "belong") "
          + "to no Project or Session.")
    }
    return make(
      id: "request:\(request.id)",
      title: "Approve Cleanup request \(request.id)?",
      message: origin(of: request),
      cautions: cautions,
      asked: request.targets,
      plan: plan,
      resume: ended.compactMap(resume),
      request: request)
  }

  // MARK: Wording

  private var now: Date { reading.snapshot.takenAt }

  private func quoted(_ text: String) -> String { "\"\(text)\"" }

  /// What a Session is doing, when a person should know before ending it.
  private func stateCaution(_ session: Session) -> String? {
    let name = quoted(session.displayTitle)
    return switch session.state {
    case .working:
      "The Session \(name) is working right now. Ending it stops that work in the middle."
    case .waiting: "The Session \(name) is waiting for your answer."
    case .background: "Work the Session \(name) started is still running in the background."
    case .unknown: "What the Session \(name) is doing cannot be told from outside."
    case .idle: nil
    }
  }

  /// Which copy of a server its Session still talks to cannot be seen from outside.
  private func duplicateCaution(_ finding: StaleFinding) -> String? {
    guard case .olderDuplicate = finding.reason else { return nil }
    return "A newer copy of \(quoted(finding.title)) runs in the same Session, so the older one "
      + "is probably left behind. If the Session still uses it, what it offers stops working there."
  }

  /// Who asked for a Cleanup request, in a sentence.
  public func origin(of request: CleanupRequest) -> String {
    guard let requester = request.requester else { return "Asked for from outside any Session." }
    guard let session = group(requester)?.session else {
      return "Asked for by a Session that has ended."
    }
    return "Asked for by the Session \(quoted(session.displayTitle)), "
      + "\(session.id.harness.label) in \(session.project.name)."
  }

  private func resume(_ session: Session) -> CleanupProposal.Resume? {
    session.resumeCommand.map {
      CleanupProposal.Resume(session: session.id, title: session.displayTitle, command: $0)
    }
  }

  // MARK: Building

  private func group(_ id: SessionID) -> SessionInventory? {
    for project in reading.inventory.projects {
      if let group = project.sessions.first(where: { $0.id == id }) { return group }
    }
    return nil
  }

  private func proposal(
    id: String, title: String, message: String, cautions: [String] = [],
    means: CleanupProposal.Means = .endProcesses, asking keys: [ProcessRecord.Key],
    resume: [CleanupProposal.Resume] = []
  ) -> CleanupProposal {
    var seen: Set<ProcessRecord.Key> = []
    let asked = keys.filter { seen.insert($0).inserted }
    return make(
      id: id, title: title, message: message, cautions: cautions, means: means, asked: asked,
      plan: planner.plan(for: asked, in: reading.snapshot), resume: resume)
  }

  private func make(
    id: String, title: String, message: String, cautions: [String],
    means: CleanupProposal.Means = .endProcesses, asked: [ProcessRecord.Key], plan: CleanupPlan,
    resume: [CleanupProposal.Resume] = [], request: CleanupRequest? = nil
  ) -> CleanupProposal {
    // Several findings can call for the same caution. It is given once.
    var given: Set<String> = []
    let cautions = cautions.filter { given.insert($0).inserted }
    return CleanupProposal(
      id: id, title: title, message: message, cautions: cautions, means: means, asked: asked,
      targets: plan.targets.map { process in
        let place = places[process.pid]
        return CleanupProposal.Target(process: process, kind: place?.kind, session: place?.session)
      },
      refused: plan.refused, resume: resume, request: request)
  }
}

extension Culprit {
  /// The command that proposes a Cleanup of this Culprit, or nil when it can only be shown.
  /// It agrees with `CleanupProposer.ending(_:)`.
  public var cleanupCommand: String? {
    if case .session = owner { return "End Session…" }
    return switch load {
    case .webContent: "End…"
    case .simulator(.some): "Shut Down…"
    case .simulator(nil), .virtualMachine, nil: nil
    }
  }
}
