import Foundation

/// Anything consuming enough CPU right now to heat the machine, attributed or not.
public struct Culprit: Sendable, Equatable, Identifiable {
  public enum Owner: Sendable, Equatable {
    case session(SessionID, Project)
    case project(Project)
    case none
  }

  public let id: String
  public let title: String
  public let owner: Owner
  /// In percent of one core, so a Culprit using four cores fully reads 400.
  public let cpuPercent: Double
  public let residentBytes: UInt64
  public let processes: [ProcessRecord.Key]

  public init(
    id: String,
    title: String,
    owner: Owner,
    cpuPercent: Double,
    residentBytes: UInt64,
    processes: [ProcessRecord.Key]
  ) {
    self.id = id
    self.title = title
    self.owner = owner
    self.cpuPercent = cpuPercent
    self.residentBytes = residentBytes
    self.processes = processes
  }
}

/// A Culprit with the time since which it has been one without a break.
public struct TrackedCulprit: Sendable, Equatable, Identifiable {
  public let culprit: Culprit
  public let hotSince: Date

  public init(culprit: Culprit, hotSince: Date) {
    self.culprit = culprit
    self.hotSince = hotSince
  }

  public var id: String { culprit.id }
}

/// Remembers since when each Culprit has been one, from one look to the next.
public struct CulpritTracker: Sendable {
  private var since: [String: Date] = [:]

  public init() {}

  public mutating func track(_ culprits: [Culprit], at now: Date) -> [TrackedCulprit] {
    var current: [String: Date] = [:]
    let tracked = culprits.map { culprit in
      let hotSince = since[culprit.id] ?? now
      current[culprit.id] = hotSince
      return TrackedCulprit(culprit: culprit, hotSince: hotSince)
    }
    // A Culprit that is gone starts over when it comes back.
    since = current
    return tracked
  }
}

/// Finds the Culprits of an Inventory and lists them from the heaviest.
public struct CulpritRanker: Sendable {
  /// CPU use, in percent of one core, from which something counts as a Culprit.
  public var threshold: Double

  public init(threshold: Double = 25) {
    self.threshold = threshold
  }

  public func culprits(
    in inventory: Inventory, usage: Usage, inducedLoad: [InducedLoad] = []
  ) -> [Culprit] {
    var loadOf: [ProcessRecord.Key: InducedLoad] = [:]
    for load in inducedLoad {
      for process in load.processes where loadOf[process] == nil {
        loadOf[process] = load
      }
    }

    var candidates: [Culprit] = []
    for project in inventory.projects {
      for group in project.sessions {
        candidates.append(
          culprit(
            id: "session:\(group.session.id)",
            title: group.session.title ?? project.project.name,
            owner: .session(group.session.id, project.project),
            processes: group.processes.map(\.process),
            usage: usage
          ))
      }
      candidates += grouped(
        project.loose.map(\.process), owner: .project(project.project),
        scope: "project:\(project.project.root)", loadOf: loadOf, usage: usage)
    }
    candidates += grouped(
      inventory.unattributed, owner: .none, scope: "machine", loadOf: loadOf, usage: usage)
    return
      candidates
      .filter { $0.cpuPercent >= threshold }
      .sorted { ($1.cpuPercent, $0.title) < ($0.cpuPercent, $1.title) }
  }

  /// Processes outside any Session, grouped by the induced load they are part of, or else by
  /// the application or name they share.
  private func grouped(
    _ processes: [ProcessRecord], owner: Culprit.Owner, scope: String,
    loadOf: [ProcessRecord.Key: InducedLoad], usage: Usage
  ) -> [Culprit] {
    struct Group: Hashable {
      let id: String
      let title: String
    }
    return Dictionary(grouping: processes) { process -> Group in
      if let load = loadOf[process.key] {
        return Group(id: "\(scope):\(load.id)", title: load.title)
      }
      let name = process.applicationOrName
      return Group(id: "\(scope):name:\(name)", title: name)
    }
    .map { group, members in
      culprit(id: group.id, title: group.title, owner: owner, processes: members, usage: usage)
    }
  }

  private func culprit(
    id: String,
    title: String,
    owner: Culprit.Owner,
    processes: [ProcessRecord],
    usage: Usage
  ) -> Culprit {
    Culprit(
      id: id,
      title: title,
      owner: owner,
      cpuPercent: processes.reduce(0) { $0 + usage.cpuPercent(of: $1.key) },
      residentBytes: processes.reduce(0) { $0 + $1.residentBytes },
      processes: processes.map(\.key)
    )
  }
}

extension ProcessRecord {
  /// The application the executable lives in, or the executable's own name outside of one.
  var applicationOrName: String {
    guard let bundle = executablePath.range(of: ".app/") else { return name }
    let before = executablePath[..<bundle.lowerBound]
    guard let slash = before.lastIndex(of: "/") else { return String(before) }
    return String(before[before.index(after: slash)...])
  }
}
