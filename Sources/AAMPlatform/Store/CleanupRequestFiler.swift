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
    // What a target started is added when the Cleanup is proposed, from what runs then.
    let plan = CleanupPlanner(ownUser: ownUser, protected: [])
      .plan(for: keys, in: reading.snapshot, includingDescendants: false)
    guard !plan.targets.isEmpty else {
      throw Refusal.nothingToAsk(plan.refused.map(\.reason))
    }

    let request = CleanupRequest(
      id: String(UUID().uuidString.lowercased().prefix(8)),
      createdAt: now,
      requester: reading.inventory.session(owning: caller)?.session.id,
      reason: reason,
      targets: plan.targets.map(\.key))
    try store.add(request)
    return (request, plan.refused)
  }
}
