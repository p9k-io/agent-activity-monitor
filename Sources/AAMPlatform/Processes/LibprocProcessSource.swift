import AAMCore
import Darwin
import Foundation

/// Reads the processes of the current user through libproc.
///
/// libproc refuses processes of other users with `EPERM`, so those are simply absent here.
public struct LibprocProcessSource: Sendable {
  private let markerNames: Set<String>
  private let nanosecondsPerTick: Double
  private let argumentBufferSize: Int

  /// A process that has ended but has not been collected by its parent.
  private static let zombieStatus: UInt32 = 5
  /// The value of the controlling terminal field when there is none.
  private static let noTerminal: UInt32 = .max

  public init(markerNames: Set<String>) {
    self.markerNames = markerNames

    var timebase = mach_timebase_info_data_t()
    mach_timebase_info(&timebase)
    nanosecondsPerTick = Double(timebase.numer) / Double(max(timebase.denom, 1))

    var maximum: Int32 = 0
    var size = MemoryLayout<Int32>.size
    var name = [CTL_KERN, KERN_ARGMAX]
    let found = sysctl(&name, 2, &maximum, &size, nil, 0) == 0 && maximum > 0
    argumentBufferSize = found ? Int(maximum) : 1 << 20
  }

  public func processes() -> [ProcessRecord] {
    var buffer = [UInt8](repeating: 0, count: argumentBufferSize)
    return identifiers().compactMap { record(for: $0, buffer: &buffer) }
  }

  /// The process with this identifier right now, or nil when it is gone or belongs to someone
  /// else.
  public func record(for pid: Int32) -> ProcessRecord? {
    var buffer = [UInt8](repeating: 0, count: argumentBufferSize)
    return record(for: pid, buffer: &buffer)
  }

  private func identifiers() -> [pid_t] {
    let estimate = proc_listallpids(nil, 0)
    guard estimate > 0 else { return [] }
    var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
    let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
    return Array(pids.prefix(Int(max(count, 0))))
  }

  private func record(for pid: pid_t, buffer: inout [UInt8]) -> ProcessRecord? {
    guard pid > 0 else { return nil }
    var all = proc_taskallinfo()
    let size = Int32(MemoryLayout<proc_taskallinfo>.size)
    guard proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, &all, size) == size else {
      // A zombie has no task left, and libproc no longer answers for it.
      return zombie(pid)
    }
    let identity = all.pbsd
    let cpuTicks = all.ptinfo.pti_total_user + all.ptinfo.pti_total_system
    let resident = all.ptinfo.pti_resident_size

    let arguments = arguments(of: pid, buffer: &buffer)
    let path = executablePath(of: pid) ?? arguments?.executablePath ?? shortName(of: identity)
    let nanoseconds = Double(cpuTicks) * nanosecondsPerTick
    return ProcessRecord(
      pid: pid,
      parentPID: Int32(identity.pbi_ppid),
      groupID: Int32(identity.pbi_pgid),
      userID: identity.pbi_uid,
      startedAt: Date(
        timeIntervalSince1970: Double(identity.pbi_start_tvsec)
          + Double(identity.pbi_start_tvusec) / 1_000_000),
      executablePath: path,
      arguments: arguments?.arguments ?? [],
      workingDirectory: workingDirectory(of: pid),
      cpuTime: .nanoseconds(Int64(nanoseconds)),
      residentBytes: resident,
      isZombie: identity.pbi_status == Self.zombieStatus,
      hasTerminal: identity.e_tdev != Self.noTerminal,
      markers: arguments?.markers ?? [:]
    )
  }

  /// The record of a process of the current user that has ended but was not collected.
  ///
  /// The kernel's process table is readable for every process; it holds identity only.
  private func zombie(_ pid: pid_t) -> ProcessRecord? {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var name = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    guard sysctl(&name, 4, &info, &size, nil, 0) == 0, size > 0,
      info.kp_proc.p_pid == pid,
      UInt32(info.kp_proc.p_stat) == Self.zombieStatus,
      info.kp_eproc.e_ucred.cr_uid == getuid()
    else { return nil }
    let started = info.kp_proc.p_starttime
    return ProcessRecord(
      pid: pid,
      parentPID: info.kp_eproc.e_ppid,
      groupID: info.kp_eproc.e_pgid,
      userID: info.kp_eproc.e_ucred.cr_uid,
      startedAt: Date(
        timeIntervalSince1970: Double(started.tv_sec) + Double(started.tv_usec) / 1_000_000),
      executablePath: withUnsafeBytes(of: info.kp_proc.p_comm) { text(in: $0) },
      arguments: [],
      workingDirectory: nil,
      cpuTime: .zero,
      residentBytes: 0,
      isZombie: true,
      hasTerminal: UInt32(bitPattern: info.kp_eproc.e_tdev) != Self.noTerminal,
      markers: [:]
    )
  }

  private func executablePath(of pid: pid_t) -> String? {
    var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
    let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
    guard length > 0 else { return nil }
    return String(decoding: buffer.prefix(Int(length)).map(UInt8.init(bitPattern:)), as: UTF8.self)
  }

  private func shortName(of identity: proc_bsdinfo) -> String {
    withUnsafeBytes(of: identity.pbi_name) { text(in: $0) }
  }

  private func workingDirectory(of pid: pid_t) -> String? {
    var info = proc_vnodepathinfo()
    let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
    guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
    let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { text(in: $0) }
    return path.isEmpty ? nil : path
  }

  private func arguments(of pid: pid_t, buffer: inout [UInt8]) -> ProcessArguments? {
    var name = [CTL_KERN, KERN_PROCARGS2, pid]
    var size = buffer.count
    let status = buffer.withUnsafeMutableBytes { sysctl(&name, 3, $0.baseAddress, &size, nil, 0) }
    guard status == 0, size > 0 else { return nil }
    return ProcessArguments.parse(Array(buffer[..<size]), markerNames: markerNames)
  }

  /// The NUL-terminated text at the start of a fixed-size C character array.
  private func text(in bytes: UnsafeRawBufferPointer) -> String {
    String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
  }
}
