import Foundation

/// The CPU time and memory one kind of process took for a Session, or loose in a Project,
/// during one minute.
public struct HistoryBucket: Sendable, Equatable {
  /// Where the minute starts.
  public let minute: Date
  public let project: Project
  /// Nil for processes that belong to the Project but to no single Session.
  public let session: SessionID?
  public let kind: ProcessKind
  public var cpuSeconds: Double
  /// The most memory the processes held together at one look.
  public var peakResidentBytes: UInt64

  public init(
    minute: Date, project: Project, session: SessionID?, kind: ProcessKind, cpuSeconds: Double,
    peakResidentBytes: UInt64
  ) {
    self.minute = minute
    self.project = project
    self.session = session
    self.kind = kind
    self.cpuSeconds = cpuSeconds
    self.peakResidentBytes = peakResidentBytes
  }
}

/// Adds what each look measures up into buckets of one minute. Single measurements are not
/// kept.
public struct HistoryRecorder: Sendable {
  private struct Key: Hashable {
    let minute: Date
    let project: Project
    let session: SessionID?
    let kind: ProcessKind
  }

  /// CPU use, in percent of one core, below which a kind of process is not counted at a
  /// look. What idles would only fill the store with rows that say nothing.
  public var busyAbove: Double

  private var buckets: [Key: (cpuSeconds: Double, peak: UInt64)] = [:]

  public init(busyAbove: Double = 1) {
    self.busyAbove = busyAbove
  }

  /// - Parameters:
  ///   - usage: CPU use since the look before.
  ///   - elapsed: The seconds since the look before.
  public mutating func record(
    _ inventory: Inventory, usage: Usage, elapsed: TimeInterval, at now: Date
  ) {
    guard elapsed > 0 else { return }
    let seconds = now.timeIntervalSinceReferenceDate
    let minute = Date(timeIntervalSinceReferenceDate: seconds - seconds.remainder(by: 60))
    for project in inventory.projects {
      for group in project.sessions {
        add(group.processes, minute, project.project, group.session.id, usage, elapsed)
      }
      add(project.loose, minute, project.project, nil, usage, elapsed)
    }
  }

  /// Takes out what was gathered, the earliest minute first.
  public mutating func drain() -> [HistoryBucket] {
    defer { buckets = [:] }
    return buckets.map { key, value in
      HistoryBucket(
        minute: key.minute, project: key.project, session: key.session, kind: key.kind,
        cpuSeconds: value.cpuSeconds, peakResidentBytes: value.peak)
    }
    .sorted {
      ($0.minute, $0.project.root, $0.session?.description ?? "", $0.kind.rawValue)
        < ($1.minute, $1.project.root, $1.session?.description ?? "", $1.kind.rawValue)
    }
  }

  private mutating func add(
    _ processes: [AttributedProcess], _ minute: Date, _ project: Project, _ session: SessionID?,
    _ usage: Usage, _ elapsed: TimeInterval
  ) {
    for (kind, members) in Dictionary(grouping: processes, by: \.kind) {
      let percent = members.reduce(0) { $0 + usage.cpuPercent(of: $1.process.key) }
      guard percent >= busyAbove else { continue }
      let memory = members.reduce(UInt64(0)) { $0 + $1.process.residentBytes }
      let key = Key(minute: minute, project: project, session: session, kind: kind)
      let before = buckets[key] ?? (0, 0)
      buckets[key] = (before.cpuSeconds + percent / 100 * elapsed, max(before.peak, memory))
    }
  }
}

extension Double {
  /// What is left after taking out whole multiples of `divisor`, never negative.
  fileprivate func remainder(by divisor: Double) -> Double {
    let rest = truncatingRemainder(dividingBy: divisor)
    return rest < 0 ? rest + divisor : rest
  }
}
