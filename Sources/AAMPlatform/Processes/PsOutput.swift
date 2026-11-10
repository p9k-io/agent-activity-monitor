import AAMCore
import Foundation

/// Reads the output of `ps`, the only public way to see processes of other users.
public enum PsOutput {
  /// The columns `parse` expects, in order. `comm` is last because it may contain spaces.
  public static let columns = "pid=,ppid=,pgid=,uid=,rss=,time=,state=,tty=,lstart=,comm="

  private static let months = [
    "Jan": 1, "Feb": 2, "Mar": 3, "Apr": 4, "May": 5, "Jun": 6,
    "Jul": 7, "Aug": 8, "Sep": 9, "Oct": 10, "Nov": 11, "Dec": 12,
  ]

  /// Lines that do not have the expected shape are skipped.
  public static func parse(_ output: String, timeZone: TimeZone = .current) -> [ProcessRecord] {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return output.split(separator: "\n").compactMap { record(from: $0, calendar: calendar) }
  }

  private static func record(from line: Substring, calendar: Calendar) -> ProcessRecord? {
    let fields = line.split(maxSplits: 13, omittingEmptySubsequences: true) { $0 == " " }
    guard
      fields.count == 14,
      let pid = Int32(fields[0]),
      let parent = Int32(fields[1]),
      let group = Int32(fields[2]),
      let user = UInt32(fields[3]),
      let residentKilobytes = UInt64(fields[4]),
      let cpuTime = duration(fields[5]),
      let startedAt = date(
        month: fields[9], day: fields[10], time: fields[11], year: fields[12], calendar: calendar)
    else { return nil }

    return ProcessRecord(
      pid: pid,
      parentPID: parent,
      groupID: group,
      userID: user,
      startedAt: startedAt,
      executablePath: fields[13].trimmingCharacters(in: .whitespaces),
      arguments: [],
      workingDirectory: nil,
      cpuTime: cpuTime,
      residentBytes: residentKilobytes * 1024,
      isZombie: fields[6].hasPrefix("Z"),
      hasTerminal: fields[7] != "??",
      markers: [:]
    )
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
    guard (2...3).contains(parts.count), let seconds = Double(parts[parts.count - 1]) else {
      return nil
    }
    guard let minutes = Int64(parts[parts.count - 2]) else { return nil }
    var hours: Int64 = 0
    if parts.count == 3 {
      guard let parsed = Int64(parts[0]) else { return nil }
      hours = parsed
    }
    let whole = ((days * 24 + hours) * 60 + minutes) * 60
    return .seconds(whole) + .milliseconds(Int64((seconds * 1000).rounded()))
  }

  private static func date(
    month: Substring,
    day: Substring,
    time: Substring,
    year: Substring,
    calendar: Calendar
  ) -> Date? {
    let clock = time.split(separator: ":").compactMap { Int($0) }
    guard let month = months[String(month)], let day = Int(day), let year = Int(year),
      clock.count == 3
    else { return nil }
    return calendar.date(
      from: DateComponents(
        year: year, month: month, day: day, hour: clock[0], minute: clock[1], second: clock[2]))
  }
}
