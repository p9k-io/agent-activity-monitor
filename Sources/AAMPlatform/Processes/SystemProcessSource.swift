import AAMCore
import Foundation
import Synchronization

/// Every process on the machine.
///
/// Identity comes from the kernel's process table. For the current user's processes, CPU time
/// and memory come from libproc on every snapshot, while the path, the arguments, the markers
/// and the working directory are read once and kept until the process replaces its program.
/// For everyone else's processes the path, CPU time and memory come from `ps`, which costs far
/// more, so a caller that samples often asks for them only now and then.
public final class SystemProcessSource: ProcessSource {
  private struct Remembered: Sendable {
    var origins: [ProcessRecord.Key: (shortName: String, origin: Libproc.Origin)] = [:]
    var others: [Int32: PsFacts] = [:]
  }

  private let libproc: Libproc
  private let remembered = Mutex(Remembered())

  public init(markerNames: Set<String>) {
    libproc = Libproc(markerNames: markerNames)
  }

  public func snapshot() -> Snapshot {
    snapshot(refreshingOtherUsers: true)
  }

  /// - Parameter refreshingOtherUsers: Whether to ask `ps` again. When false, what was learned
  ///   about other users' processes the last time is carried over unchanged.
  public func snapshot(refreshingOtherUsers: Bool) -> Snapshot {
    let takenAt = Date()
    let table = KernelProcessTable.read()
    let me = getuid()
    let fresh =
      refreshingOtherUsers
      ? PsRunner.facts(ofUsers: Set(table.lazy.map(\.userID).filter { $0 != me })) : nil
    var buffer = [UInt8](repeating: 0, count: libproc.argumentBufferSize)

    let processes = remembered.withLock { remembered -> [ProcessRecord] in
      if let fresh {
        remembered.others = fresh
      }
      var alive: Set<ProcessRecord.Key> = []
      let records = table.compactMap { entry -> ProcessRecord? in
        if entry.isZombie {
          return Self.record(entry, path: entry.shortName)
        }
        guard entry.userID == me else {
          return Self.record(entry, facts: remembered.others[entry.pid])
        }
        guard let vitals = libproc.vitals(of: entry.pid) else { return nil }
        let key = ProcessRecord.Key(pid: entry.pid, startedAt: entry.startedAt)
        alive.insert(key)
        let origin: Libproc.Origin
        if let known = remembered.origins[key], known.shortName == entry.shortName {
          origin = known.origin
        } else {
          origin = libproc.origin(of: entry.pid, buffer: &buffer)
          remembered.origins[key] = (entry.shortName, origin)
        }
        return Self.record(entry, vitals: vitals, origin: origin)
      }
      remembered.origins = remembered.origins.filter { alive.contains($0.key) }
      return records
    }
    return Snapshot(takenAt: takenAt, processes: processes)
  }

  /// The current user's process with this identifier right now, read afresh. Nil when it is
  /// gone or belongs to someone else.
  public func record(for pid: Int32) -> ProcessRecord? {
    guard let entry = KernelProcessTable.process(pid), entry.userID == getuid() else { return nil }
    if entry.isZombie {
      return Self.record(entry, path: entry.shortName)
    }
    guard let vitals = libproc.vitals(of: pid) else { return nil }
    var buffer = [UInt8](repeating: 0, count: libproc.argumentBufferSize)
    return Self.record(entry, vitals: vitals, origin: libproc.origin(of: pid, buffer: &buffer))
  }

  // MARK: Records

  private static func record(
    _ entry: KernelProcess, vitals: Libproc.Vitals, origin: Libproc.Origin
  ) -> ProcessRecord {
    record(
      entry, path: origin.executablePath ?? entry.shortName, arguments: origin.arguments,
      workingDirectory: origin.workingDirectory, cpuTime: vitals.cpuTime,
      residentBytes: vitals.residentBytes, markers: origin.markers)
  }

  private static func record(_ entry: KernelProcess, facts: PsFacts?) -> ProcessRecord {
    record(
      entry, path: facts?.executablePath ?? entry.shortName, cpuTime: facts?.cpuTime ?? .zero,
      residentBytes: facts?.residentBytes ?? 0)
  }

  private static func record(
    _ entry: KernelProcess,
    path: String,
    arguments: [String] = [],
    workingDirectory: String? = nil,
    cpuTime: Duration = .zero,
    residentBytes: UInt64 = 0,
    markers: [String: String] = [:]
  ) -> ProcessRecord {
    ProcessRecord(
      pid: entry.pid,
      parentPID: entry.parentPID,
      groupID: entry.groupID,
      userID: entry.userID,
      startedAt: entry.startedAt,
      executablePath: path,
      arguments: arguments,
      workingDirectory: workingDirectory,
      cpuTime: cpuTime,
      residentBytes: residentBytes,
      isZombie: entry.isZombie,
      hasTerminal: entry.hasTerminal,
      markers: markers
    )
  }
}
