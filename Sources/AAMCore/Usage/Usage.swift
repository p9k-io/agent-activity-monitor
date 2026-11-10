import Foundation

/// CPU use of each process between two snapshots, in percent of one core.
public struct Usage: Sendable {
  private let percentByKey: [ProcessRecord.Key: Double]

  public init(previous: Snapshot, current: Snapshot) {
    let elapsed = current.takenAt.timeIntervalSince(previous.takenAt)
    guard elapsed > 0 else {
      percentByKey = [:]
      return
    }
    let earlier = Dictionary(
      previous.processes.map { ($0.key, $0.cpuTime) }, uniquingKeysWith: { first, _ in first })
    var percent: [ProcessRecord.Key: Double] = [:]
    for process in current.processes {
      guard let before = earlier[process.key] else { continue }
      let spent = (process.cpuTime - before).seconds
      percent[process.key] = max(0, spent / elapsed * 100)
    }
    percentByKey = percent
  }

  /// A measurement given directly, for processes measured some other way.
  public init(_ percentByKey: [ProcessRecord.Key: Double]) {
    self.percentByKey = percentByKey
  }

  /// This measurement for the processes `includes` accepts, and nothing for the rest.
  public func limited(to includes: (ProcessRecord.Key) -> Bool) -> Usage {
    Usage(percentByKey.filter { includes($0.key) })
  }

  /// Both measurements together. Where both know a process, `other` wins.
  public func merging(_ other: Usage) -> Usage {
    Usage(percentByKey.merging(other.percentByKey) { _, theirs in theirs })
  }

  /// Zero for a process that was not in the earlier snapshot: nothing has been measured yet.
  public func cpuPercent(of key: ProcessRecord.Key) -> Double {
    percentByKey[key] ?? 0
  }
}

extension Duration {
  var seconds: Double {
    Double(components.seconds) + Double(components.attoseconds) / 1e18
  }
}
