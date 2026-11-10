import AAMCore
import Foundation

/// Files a Cleanup request for a person to decide in the app. Nothing is ended by filing.
///
/// Whoever calls it is not trusted to say who they are: the Session a request comes from is
/// found from the process tree.
public struct CleanupRequestFiler: Sendable {
  /// Why a request was not filed.
  public enum Refusal: Error, Equatable, CustomStringConvertible {
    /// None of the processes can be asked for, with the reason for each.
    case nothingToAsk([CleanupPlan.Reason])
    case tooManyProcesses
    case tooManyPending

    public var description: String {
      switch self {
      case .nothingToAsk(let reasons):
        "Nothing to ask for: " + reasons.map(\.explanation).joined(separator: "; ") + "."
      case .tooManyProcesses:
        "A Cleanup request takes at most \(CleanupRequestFiler.processLimit) processes."
      case .tooManyPending:
        "\(CleanupRequestFiler.pendingLimit) Cleanup requests already wait for a decision in "
          + "the app. Ask again once they are decided."
      }
    }
  }

  /// How many processes one request may name.
  public static let processLimit = 100
  /// How many requests may wait for a decision at a time, so that a Session that keeps asking
  /// cannot bury the ones that matter.
  public static let pendingLimit = 50

  private let store: Store
  private let ownUser: UInt32

  public init(store: Store, ownUser: UInt32 = getuid()) {
    self.store = store
    self.ownUser = ownUser
  }

  /// - Parameters:
  ///   - reading: What the machine looks like now.
  ///   - caller: The process that asks. Its Session becomes the requester.
  /// - Returns: The request as it was stored, and the processes that were left out of it.
  public func file(
    pids: [Int32], reason: String, in reading: Reading, caller: Int32 = getpid(),
    now: Date = Date()
  ) throws -> (request: CleanupRequest, refused: [CleanupPlan.Refusal]) {
    guard pids.count <= Self.processLimit else { throw Refusal.tooManyProcesses }
    guard try store.requests(status: .pending).count < Self.pendingLimit else {
      throw Refusal.tooManyPending
    }

    var seen: Set<Int32> = []
    // A process that is not there is asked for by a key nothing can match, so that the
    // planner reports it as gone.
    let keys = pids.filter { seen.insert($0).inserted }.map { pid in
      reading.snapshot.processes.first { $0.pid == pid }?.key
        ?? ProcessRecord.Key(pid: pid, startedAt: .distantPast)
    }
    // A request is for what a Session left around. What belongs to no Project or Session is
    // a person's own: a browser, a virtual machine, the login window.
    let attributed = Set(
      reading.inventory.projects.flatMap { project in
        project.loose.map(\.process.key)
          + project.sessions.flatMap { $0.processes.map(\.process.key) }
      })
    let present = Set(reading.snapshot.processes.map(\.key))
    let outside = keys.filter { present.contains($0) && !attributed.contains($0) }
    var refused = outside.map { CleanupPlan.Refusal(process: $0, reason: .unattributed) }

    // What a target started is added when the Cleanup is proposed, from what runs then.
    let plan = CleanupPlanner(ownUser: ownUser, protected: [])
      .plan(
        for: keys.filter { !outside.contains($0) }, in: reading.snapshot,
        includingDescendants: false)
    refused += plan.refused
    guard !plan.targets.isEmpty else {
      throw Refusal.nothingToAsk(refused.map(\.reason))
    }

    let request = CleanupRequest(
      id: String(UUID().uuidString.lowercased().prefix(8)),
      createdAt: now,
      requester: requester(for: caller, in: reading),
      reason: reason,
      targets: plan.targets.map(\.key))
    try store.add(request)
    return (request, refused)
  }

  /// The Session whose tree the caller is in. A marker in the caller's environment is not
  /// enough: anything can set one and ask in a Session's name.
  private func requester(for caller: Int32, in reading: Reading) -> SessionID? {
    guard let group = reading.inventory.session(owning: caller),
      group.processes.contains(where: { $0.process.pid == caller && $0.evidence == .tree })
    else { return nil }
    return group.session.id
  }
}
