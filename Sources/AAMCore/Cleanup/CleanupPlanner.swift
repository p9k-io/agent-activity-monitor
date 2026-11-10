/// What a Cleanup would end, decided before any signal is sent.
public struct CleanupPlan: Sendable, Equatable {
  /// Why a process that was asked for is left alone.
  public enum Reason: String, Sendable, Codable {
    /// The process has ended, or its identifier belongs to another process now.
    case gone
    /// The process belongs to another user.
    case notYours
    /// The process must never be ended: the system's first process, or one the planner was
    /// told to protect.
    case protected
    /// The process has ended already and only waits to be collected by its parent.
    case zombie
  }

  public struct Refusal: Sendable, Equatable {
    public let process: ProcessRecord.Key
    public let reason: Reason

    public init(process: ProcessRecord.Key, reason: Reason) {
      self.process = process
      self.reason = reason
    }
  }

  /// The processes to end, each one before the processes it started.
  public let targets: [ProcessRecord]
  public let refused: [Refusal]

  public init(targets: [ProcessRecord], refused: [Refusal]) {
    self.targets = targets
    self.refused = refused
  }
}

/// Turns the processes someone asked to end into the processes that may be ended.
///
/// A process is identified by its identifier together with its start time, so an identifier
/// the system has reused is never mistaken for the process that was meant.
public struct CleanupPlanner: Sendable {
  private let ownUser: UInt32
  private let protected: Set<Int32>

  /// - Parameters:
  ///   - ownUser: Only this user's processes may be ended.
  ///   - protected: Processes that must be left running, such as the app itself.
  public init(ownUser: UInt32, protected: Set<Int32>) {
    self.ownUser = ownUser
    self.protected = protected
  }

  /// - Parameter includingDescendants: Whether what a target started is ended with it.
  public func plan(
    for keys: [ProcessRecord.Key],
    in snapshot: Snapshot,
    includingDescendants: Bool = true
  ) -> CleanupPlan {
    let tree = ProcessTree(snapshot.processes)
    var refused: [CleanupPlan.Refusal] = []
    var chosen: [Int32: ProcessRecord] = [:]

    for key in keys {
      guard let process = tree.process(key.pid), process.key == key else {
        refused.append(CleanupPlan.Refusal(process: key, reason: .gone))
        continue
      }
      if let reason = refusal(of: process) {
        if chosen[process.pid] == nil, !refused.contains(where: { $0.process == key }) {
          refused.append(CleanupPlan.Refusal(process: key, reason: reason))
        }
        continue
      }
      chosen[process.pid] = process
      guard includingDescendants else { continue }
      for descendant in descendants(of: process, in: tree) {
        chosen[descendant.pid] = descendant
      }
    }

    let depth = Dictionary(
      uniqueKeysWithValues: chosen.keys.map { ($0, tree.ancestors(of: $0).count) })
    return CleanupPlan(
      targets: chosen.values.sorted { left, right in
        (depth[left.pid] ?? 0, left.pid) < (depth[right.pid] ?? 0, right.pid)
      },
      refused: refused)
  }

  /// What a process started, without what may not be ended and without anything below that.
  private func descendants(of process: ProcessRecord, in tree: ProcessTree) -> [ProcessRecord] {
    var result: [ProcessRecord] = []
    var pending = tree.children(of: process.pid)
    while let next = pending.popLast() {
      guard refusal(of: next) == nil else { continue }
      result.append(next)
      pending.append(contentsOf: tree.children(of: next.pid))
    }
    return result
  }

  private func refusal(of process: ProcessRecord) -> CleanupPlan.Reason? {
    if process.pid <= 1 || protected.contains(process.pid) { return .protected }
    if process.userID != ownUser { return .notYours }
    if process.isZombie { return .zombie }
    return nil
  }
}
