import Foundation

/// A process as it was seen at one moment.
public struct ProcessRecord: Sendable, Equatable, Identifiable {
  /// Identifies one process for its whole life. The system reuses process identifiers, so the
  /// identifier alone is not enough.
  public struct Key: Hashable, Sendable, Codable {
    public let pid: Int32
    public let startedAt: Date

    public init(pid: Int32, startedAt: Date) {
      self.pid = pid
      self.startedAt = startedAt
    }
  }

  public let pid: Int32
  public let parentPID: Int32
  public let groupID: Int32
  public let userID: UInt32
  public let startedAt: Date
  public let executablePath: String
  public let arguments: [String]
  public let workingDirectory: String?
  /// CPU time consumed since the process started.
  public let cpuTime: Duration
  public let residentBytes: UInt64
  public let isZombie: Bool
  public let hasTerminal: Bool
  /// Values of the environment variables on the marker list, where the system exposes them.
  public let markers: [String: String]

  public init(
    pid: Int32,
    parentPID: Int32,
    groupID: Int32,
    userID: UInt32,
    startedAt: Date,
    executablePath: String,
    arguments: [String],
    workingDirectory: String?,
    cpuTime: Duration,
    residentBytes: UInt64,
    isZombie: Bool,
    hasTerminal: Bool,
    markers: [String: String]
  ) {
    self.pid = pid
    self.parentPID = parentPID
    self.groupID = groupID
    self.userID = userID
    self.startedAt = startedAt
    self.executablePath = executablePath
    self.arguments = arguments
    self.workingDirectory = workingDirectory
    self.cpuTime = cpuTime
    self.residentBytes = residentBytes
    self.isZombie = isZombie
    self.hasTerminal = hasTerminal
    self.markers = markers
  }

  public var key: Key { Key(pid: pid, startedAt: startedAt) }
  public var id: Key { key }

  /// The last component of the executable path.
  public var name: String {
    // Asked for every process on every look, so it avoids splitting the whole path.
    guard let slash = executablePath.lastIndex(of: "/") else { return executablePath }
    let last = executablePath[executablePath.index(after: slash)...]
    if !last.isEmpty { return String(last) }
    return executablePath.split(separator: "/").last.map(String.init) ?? executablePath
  }
}

/// Every process visible at one moment.
public struct Snapshot: Sendable, Equatable {
  public let takenAt: Date
  public let processes: [ProcessRecord]

  public init(takenAt: Date, processes: [ProcessRecord]) {
    self.takenAt = takenAt
    self.processes = processes
  }
}
