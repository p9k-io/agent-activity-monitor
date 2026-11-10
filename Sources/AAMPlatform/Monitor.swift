import AAMCore
import Foundation

/// What one look found, with what is remembered after it.
public struct Look: Sendable {
  public let observation: Reading
  public let memory: Memory
  /// CPU use since the look before, when there was one.
  public let usage: Usage?
}

/// Looks at the machine with what the store remembers, and remembers what it saw.
///
/// The store is optional and never in the way: when it cannot be read or written, the look
/// works from what it sees alone.
public struct Monitor: Sendable {
  /// How long an ended Session is remembered.
  private static let retention: TimeInterval = 30 * 24 * 3600

  private let observer: Observer
  private let store: Store?

  public init(observer: Observer = .system(), store: Store?) {
    self.observer = observer
    self.store = store
  }

  /// A Monitor of this machine that uses the store in its usual place when it can be opened.
  public static func system() -> Monitor {
    Monitor(store: try? Store(url: Store.defaultURL))
  }

  /// - Parameter previous: The look before this one. With it, CPU use is measured and activity
  ///   is recorded. Without it, only what belongs where is remembered.
  public func look(after previous: Reading? = nil) -> Look {
    var memory = (try? store?.loadMemory()) ?? .empty
    let observation = observer.observe(remembering: memory)
    let usage = previous.map { Usage(previous: $0.snapshot, current: observation.snapshot) }
    memory.absorb(observation, usage: usage)
    memory.forget(
      sessionsEndedBefore: observation.snapshot.takenAt.addingTimeInterval(-Self.retention))
    try? store?.save(memory)
    return Look(observation: observation, memory: memory, usage: usage)
  }

  /// The induced load among the processes of an observation.
  public func inducedLoad(in observation: Reading) -> [InducedLoad] {
    observer.inducedLoad(in: observation.snapshot)
  }
}
