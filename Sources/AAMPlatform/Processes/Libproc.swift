import Darwin
import Foundation

/// What libproc tells about a process of the current user. For processes of other users it
/// answers `EPERM`.
struct Libproc: Sendable {
  /// The facts that change all the time.
  struct Vitals {
    let cpuTime: Duration
    let residentBytes: UInt64
  }

  /// The facts that stay the same until the process replaces its program.
  struct Origin: Sendable {
    let executablePath: String?
    let arguments: [String]
    let markers: [String: String]
    let workingDirectory: String?
  }

  private let markerNames: Set<String>
  private let nanosecondsPerTick: Double
  let argumentBufferSize: Int

  init(markerNames: Set<String>) {
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

  /// Nil when the process is gone, is a zombie or belongs to someone else.
  func vitals(of pid: pid_t) -> Vitals? {
    var info = proc_taskinfo()
    let size = Int32(MemoryLayout<proc_taskinfo>.size)
    guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { return nil }
    let ticks = info.pti_total_user + info.pti_total_system
    return Vitals(
      cpuTime: .nanoseconds(Int64(Double(ticks) * nanosecondsPerTick)),
      residentBytes: info.pti_resident_size)
  }

  func origin(of pid: pid_t, buffer: inout [UInt8]) -> Origin {
    let arguments = arguments(of: pid, buffer: &buffer)
    return Origin(
      executablePath: executablePath(of: pid) ?? arguments?.executablePath,
      arguments: arguments?.arguments ?? [],
      markers: arguments?.markers ?? [:],
      workingDirectory: workingDirectory(of: pid))
  }

  private func executablePath(of pid: pid_t) -> String? {
    var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
    let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
    guard length > 0 else { return nil }
    return String(decoding: buffer.prefix(Int(length)).map(UInt8.init(bitPattern:)), as: UTF8.self)
  }

  private func workingDirectory(of pid: pid_t) -> String? {
    var info = proc_vnodepathinfo()
    let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
    guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
    let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) {
      String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
    }
    return path.isEmpty ? nil : path
  }

  private func arguments(of pid: pid_t, buffer: inout [UInt8]) -> ProcessArguments? {
    var name = [CTL_KERN, KERN_PROCARGS2, pid]
    var size = buffer.count
    let status = buffer.withUnsafeMutableBytes { sysctl(&name, 3, $0.baseAddress, &size, nil, 0) }
    guard status == 0, size > 0 else { return nil }
    return ProcessArguments.parse(Array(buffer[..<size]), markerNames: markerNames)
  }
}
