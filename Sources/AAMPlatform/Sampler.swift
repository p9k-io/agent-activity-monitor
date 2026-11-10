import AAMCore
import Foundation

/// A process source that can be told to leave out its expensive part.
public protocol SamplingSource: ProcessSource {
  /// - Parameter refreshingOtherUsers: When false, what is known about other users' processes
  ///   is carried over from the last time it was asked for.
  func snapshot(refreshingOtherUsers: Bool) -> Snapshot
}

extension SystemProcessSource: SamplingSource {}

/// Everything one look of the Sampler found.
public struct Sample: Sendable {
  public let observation: Reading
  public let usage: Usage
  public let memory: Memory
  public let culprits: [TrackedCulprit]
  public let inducedLoad: [InducedLoad]
  public let findings: [StaleFinding]

  public var takenAt: Date { observation.snapshot.takenAt }
}

/// Looks at the machine again and again, measuring CPU use from one look to the next and
/// remembering what it saw.
///
/// It is built to run all the time: the current user's processes are looked at on every tick,
/// everyone else's only on every few, and what is remembered is written to the store now and
/// then instead of every time.
public actor Sampler {
  public struct Settings: Sendable, Equatable {
    public var thresholds: StaleThresholds
    /// CPU use, in percent of one core, from which something counts as a Culprit.
    public var culpritThreshold: Double

    public init(thresholds: StaleThresholds = StaleThresholds(), culpritThreshold: Double = 25) {
      self.thresholds = thresholds
      self.culpritThreshold = culpritThreshold
    }
  }

  /// How long an ended Session is remembered.
  private static let retention: TimeInterval = 30 * 24 * 3600

  private let source: any SamplingSource
  private let observer: Observer
  private let store: Store?
  private let ownUser: UInt32
  private let refreshOthersEvery: Int
  private let saveEvery: Int

  private var settings: Settings
  private var memory: Memory
  private var tracker = CulpritTracker()
  private var ticks = 0
  private var previous: Snapshot?
  private var lastRefresh: Snapshot?
  private var othersUsage = Usage([:])

  /// - Parameters:
  ///   - ownUser: The user whose processes are measured on every tick.
  ///   - refreshOthersEvery: Other users' processes are asked about on every this-many-th tick.
  ///   - saveEvery: What is remembered is written to the store on every this-many-th tick.
  public init(
    source: any SamplingSource,
    observer: Observer,
    store: Store?,
    settings: Settings = Settings(),
    ownUser: UInt32 = getuid(),
    refreshOthersEvery: Int = 6,
    saveEvery: Int = 6
  ) {
    self.source = source
    self.observer = observer
    self.store = store
    self.settings = settings
    self.ownUser = ownUser
    self.refreshOthersEvery = max(1, refreshOthersEvery)
    self.saveEvery = max(1, saveEvery)
    memory = (try? store?.loadMemory()) ?? .empty
  }

  /// A Sampler of this machine that keeps what it remembers in the store in its usual place.
  public static func system() -> Sampler {
    let parts = SystemParts()
    return Sampler(
      source: parts.source, observer: parts.observer, store: try? Store(url: Store.defaultURL))
  }

  public func update(_ settings: Settings) {
    self.settings = settings
  }

  /// Takes one look.
  public func tick() -> Sample {
    let refreshing = ticks % refreshOthersEvery == 0
    let saving = ticks % saveEvery == 0
    ticks += 1

    let snapshot = source.snapshot(refreshingOtherUsers: refreshing)
    let now = snapshot.takenAt
    let observation = observer.observe(snapshot, remembering: memory)
    let usage = measure(snapshot, refreshed: refreshing)

    memory.absorb(observation, usage: previous == nil ? nil : usage)
    memory.forget(sessionsEndedBefore: now.addingTimeInterval(-Self.retention))
    if saving {
      try? store?.save(memory)
    }
    previous = snapshot

    let inducedLoad = observer.inducedLoad(in: snapshot)
    let culprits = CulpritRanker(threshold: settings.culpritThreshold)
      .culprits(in: observation.inventory, usage: usage, inducedLoad: inducedLoad)
    return Sample(
      observation: observation,
      usage: usage,
      memory: memory,
      culprits: tracker.track(culprits, at: now),
      inducedLoad: inducedLoad,
      findings: StalenessRules(thresholds: settings.thresholds)
        .findings(in: observation.inventory, memory: memory, now: now))
  }

  /// Writes what is remembered to the store now, as before the app quits.
  public func flush() {
    try? store?.save(memory)
  }

  /// CPU use of every process. The current user's processes are measured since the look
  /// before; everyone else's since the last time they were asked about, because between
  /// those times nothing new is known about them.
  private func measure(_ snapshot: Snapshot, refreshed: Bool) -> Usage {
    let own = Set(snapshot.processes.lazy.filter { $0.userID == self.ownUser }.map(\.key))
    let ownUsage =
      previous.map { Usage(previous: $0, current: snapshot).limited { own.contains($0) } }
      ?? Usage([:])
    if refreshed {
      if let lastRefresh {
        othersUsage = Usage(previous: lastRefresh, current: snapshot)
          .limited { !own.contains($0) }
      }
      lastRefresh = snapshot
    }
    return ownUsage.merging(othersUsage)
  }
}
