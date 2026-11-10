import Darwin
import Foundation

/// The identity of a process as the kernel's process table holds it.
public struct KernelProcess: Sendable, Equatable {
  public let pid: Int32
  public let parentPID: Int32
  public let groupID: Int32
  public let userID: UInt32
  public let startedAt: Date
  /// Ended, but not yet collected by its parent.
  public let isZombie: Bool
  public let hasTerminal: Bool
  /// The first characters of the program's name. It changes when the process replaces its
  /// program.
  public let shortName: String
}

/// Reads the kernel's process table. It is readable for every process, whoever owns it, and
/// holds identity only: no CPU time, no memory, no path.
public enum KernelProcessTable {
  private static let zombieStatus: Int8 = 5
  private static let noTerminal: Int32 = -1

  public static func read() -> [KernelProcess] {
    var name = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
    var size = 0
    guard sysctl(&name, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }
    let stride = MemoryLayout<kinfo_proc>.stride
    // Room for processes started between the two calls.
    var entries = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + 64)
    size = entries.count * stride
    guard sysctl(&name, 4, &entries, &size, nil, 0) == 0 else { return [] }
    return entries.prefix(size / stride).compactMap(process)
  }

  /// The process with this identifier, or nil when there is none.
  public static func process(_ pid: Int32) -> KernelProcess? {
    var entry = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var name = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    guard sysctl(&name, 4, &entry, &size, nil, 0) == 0, size > 0, entry.kp_proc.p_pid == pid
    else { return nil }
    return process(entry)
  }

  private static func process(_ entry: kinfo_proc) -> KernelProcess? {
    guard entry.kp_proc.p_pid > 0 else { return nil }
    let started = entry.kp_proc.p_starttime
    return KernelProcess(
      pid: entry.kp_proc.p_pid,
      parentPID: entry.kp_eproc.e_ppid,
      groupID: entry.kp_eproc.e_pgid,
      userID: entry.kp_eproc.e_ucred.cr_uid,
      startedAt: Date(
        timeIntervalSince1970: Double(started.tv_sec) + Double(started.tv_usec) / 1_000_000),
      isZombie: entry.kp_proc.p_stat == zombieStatus,
      hasTerminal: entry.kp_eproc.e_tdev != noTerminal,
      shortName: withUnsafeBytes(of: entry.kp_proc.p_comm) {
        String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
      }
    )
  }
}
