import AAMCore
import AAMPlatform
import Darwin
import Foundation

/// What became of the processes a Cleanup was asked to end.
public struct CleanupResult: Sendable, Equatable {
  /// Exited after being asked to.
  public var ended: [ProcessRecord.Key] = []
  /// Did not exit in time and were ended by force.
  public var endedByForce: [ProcessRecord.Key] = []
  /// Still running after everything.
  public var survived: [ProcessRecord.Key] = []
  /// Left alone, with the reason.
  public var refused: [CleanupPlan.Refusal] = []

  public init() {}

  /// The same in numbers, as it is recorded with a Cleanup request.
  public var outcome: CleanupRequest.Outcome {
    CleanupRequest.Outcome(
      ended: ended.count, endedByForce: endedByForce.count, survived: survived.count,
      refused: refused.count)
  }
}

/// Ends processes: asks them to exit, waits, and ends by force what is still there.
///
/// This is the only code that sends a signal to a process, and it lives in a module that only
/// the app links. It must be called only after a person has confirmed the Cleanup.
public struct Terminator: Sendable {
  /// How long a process ended by force is waited for.
  private static let patience: Duration = .seconds(2)
  private static let pollInterval: Duration = .milliseconds(100)

  /// The rules this Terminator ends by. A proposal made with them shows what it would do.
  public let planner: CleanupPlanner
  /// How long a process has to exit after being asked to, before it is ended by force.
  public let grace: Duration
  private let source: SystemProcessSource

  /// - Parameters:
  ///   - grace: How long a process has to exit after being asked to.
  ///   - protected: Processes never to end. By default the current process and those above it.
  public init(
    source: SystemProcessSource,
    grace: Duration = .seconds(5),
    protected: Set<Int32>? = nil
  ) {
    self.source = source
    self.grace = grace
    planner = CleanupPlanner(ownUser: getuid(), protected: protected ?? Self.selfAndAncestors())
  }

  /// Ends exactly the processes given, and nothing they started since: a person confirmed a
  /// list, and that list is all that may be ended. What has gone, changed hands or may not be
  /// ended any more is left out.
  public func end(_ keys: [ProcessRecord.Key]) async -> CleanupResult {
    let plan = planner.plan(
      for: keys, in: source.snapshot(refreshingOtherUsers: false), includingDescendants: false)
    var result = CleanupResult()
    result.refused = plan.refused

    let targets = plan.targets.map(\.key)
    send(SIGTERM, to: targets)
    let stubborn = await waitForExit(of: targets, upTo: grace)
    result.ended = targets.filter { !stubborn.contains($0) }

    send(SIGKILL, to: stubborn)
    result.survived = await waitForExit(of: stubborn, upTo: Self.patience)
    result.endedByForce = stubborn.filter { !result.survived.contains($0) }
    return result
  }

  private func send(_ signal: Int32, to keys: [ProcessRecord.Key]) {
    // Checked again right before the signal: the identifier must still name the same process.
    for key in keys where isRunning(key) {
      kill(key.pid, signal)
    }
  }

  /// Waits until the processes have exited or the time is up. Returns those still running.
  private func waitForExit(
    of keys: [ProcessRecord.Key], upTo limit: Duration
  ) async -> [ProcessRecord.Key] {
    let deadline = ContinuousClock.now + limit
    var running = keys.filter(isRunning)
    while !running.isEmpty, ContinuousClock.now < deadline {
      try? await Task.sleep(for: Self.pollInterval)
      running = running.filter(isRunning)
    }
    return running
  }

  /// A zombie has exited already; it only waits for its parent.
  private func isRunning(_ key: ProcessRecord.Key) -> Bool {
    guard let process = KernelProcessTable.process(key.pid) else { return false }
    return process.startedAt == key.startedAt && !process.isZombie
  }

  private static func selfAndAncestors() -> Set<Int32> {
    var protected: Set<Int32> = []
    var next: Int32? = getpid()
    while let pid = next, pid > 1, protected.insert(pid).inserted {
      next = KernelProcessTable.process(pid)?.parentPID
    }
    return protected
  }
}
