import Foundation

/// What `ps` knows about a process that nothing else tells an unprivileged caller about the
/// processes of other users.
public struct PsFacts: Sendable, Equatable {
  public let residentBytes: UInt64
  public let cpuTime: Duration
  public let executablePath: String
}

/// Reads the output of `ps`, the only public way to see the CPU time and memory of processes
/// of other users.
public enum PsOutput {
  /// The columns `parse` expects, in order. `comm` is last because it may contain spaces. The
  /// list is short on purpose: `ps` takes four times as long when asked for more.
  public static let columns = "pid=,rss=,time=,comm="

  /// Lines that do not have the expected shape are skipped.
  public static func parse(_ output: String) -> [Int32: PsFacts] {
    var facts: [Int32: PsFacts] = [:]
    for line in output.split(separator: "\n") {
      let fields = line.split(maxSplits: 3, omittingEmptySubsequences: true) { $0 == " " }
      guard fields.count == 4, let pid = Int32(fields[0]), let kilobytes = UInt64(fields[1]),
        let cpuTime = duration(fields[2])
      else { continue }
      facts[pid] = PsFacts(
        residentBytes: kilobytes * 1024, cpuTime: cpuTime,
        executablePath: fields[3].trimmingCharacters(in: .whitespaces))
    }
    return facts
  }

  /// Reads `[[dd-]hh:]mm:ss.cc`.
  private static func duration(_ text: Substring) -> Duration? {
    var rest = text
    var days: Int64 = 0
    if let dash = rest.firstIndex(of: "-") {
      guard let parsed = Int64(rest[..<dash]) else { return nil }
      days = parsed
      rest = rest[rest.index(after: dash)...]
    }
    let parts = rest.split(separator: ":")
    guard (2...3).contains(parts.count), let seconds = Double(parts[parts.count - 1]),
      let minutes = Int64(parts[parts.count - 2])
    else { return nil }
    var hours: Int64 = 0
    if parts.count == 3 {
      guard let parsed = Int64(parts[0]) else { return nil }
      hours = parsed
    }
    let whole = ((days * 24 + hours) * 60 + minutes) * 60
    return .seconds(whole) + .milliseconds(Int64((seconds * 1000).rounded()))
  }
}

/// Runs `/bin/ps`, which is setuid root and therefore sees every process.
enum PsRunner {
  /// The facts about the processes of the given users. Asking only about them costs a
  /// fraction of asking about everyone.
  static func facts(ofUsers users: Set<UInt32>) -> [Int32: PsFacts] {
    guard !users.isEmpty else { return [:] }
    let ps = Process()
    ps.executableURL = URL(fileURLWithPath: "/bin/ps")
    ps.arguments = [
      "-x", "-U", users.sorted().map(String.init).joined(separator: ","), "-o", PsOutput.columns,
    ]
    // Number formats must not depend on the user's locale.
    ps.environment = ["LC_ALL": "C"]
    let output = Pipe()
    ps.standardOutput = output
    ps.standardError = FileHandle.nullDevice
    do {
      try ps.run()
    } catch {
      return [:]
    }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    ps.waitUntilExit()
    return PsOutput.parse(String(decoding: data, as: UTF8.self))
  }
}
