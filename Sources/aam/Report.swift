import AAMCore
import AAMPlatform
import ArgumentParser
import Foundation

struct Report: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Show where CPU time went over the last days, per Session and Project.",
    discussion: """
      History is recorded while the Agent Activity Monitor app is running, and kept for 30 \
      days. What uses less than 1 % of one core is not counted.
      """
  )

  @Option(name: .long, help: "How many days back to look, from 1 to 30.")
  var days = 7

  @OptionGroup var output: OutputOptions

  func validate() throws {
    guard (1...30).contains(days) else {
      throw ValidationError("--days must be between 1 and 30.")
    }
  }

  func run() throws {
    let now = Date()
    let since = now.addingTimeInterval(-Double(days) * 86_400)
    guard let usage = try? Store(url: Store.defaultURL).usageReport(since: since) else {
      FileHandle.standardError.write(
        Data("aam: the store at \(Store.defaultURL.path) cannot be read.\n".utf8))
      throw ExitCode(1)
    }
    let report = UsageRows(usage, days: days, since: since)
    if output.json {
      try printJSON(report)
    } else {
      print(report.text)
    }
  }
}

/// The shape `aam report --json` prints.
struct UsageRows: Encodable {
  struct ProjectRow: Encodable {
    let name: String
    let root: String
    let cpuSeconds: Double
  }

  struct KindRow: Encodable {
    let kind: String
    let cpuSeconds: Double
  }

  struct SessionRow: Encodable {
    let project: String
    let projectRoot: String
    /// Nil for what belongs to the Project but to no single Session.
    let session: String?
    let title: String
    let cpuSeconds: Double
    let peakResidentBytes: UInt64
    let byKind: [KindRow]
  }

  let since: Date
  let days: Int
  let cpuSeconds: Double
  let projects: [ProjectRow]
  let sessions: [SessionRow]

  init(_ report: UsageReport, days: Int, since: Date) {
    self.since = since
    self.days = days
    cpuSeconds = report.cpuSeconds
    projects = report.projects.map {
      ProjectRow(name: $0.project.name, root: $0.project.root, cpuSeconds: $0.cpuSeconds)
    }
    sessions = report.rows.map { row in
      SessionRow(
        project: row.project.name, projectRoot: row.project.root,
        session: row.session?.description, title: row.title, cpuSeconds: row.cpuSeconds,
        peakResidentBytes: row.peakResidentBytes,
        byKind: row.byKind.map { KindRow(kind: $0.kind.rawValue, cpuSeconds: $0.cpuSeconds) })
    }
  }

  var text: String {
    guard !sessions.isEmpty else {
      return "Nothing was recorded in the last \(days) days. "
        + "History is kept while the Agent Activity Monitor app is running."
    }
    let table = columns(
      ["CPU TIME", "PEAK MEMORY", "PROJECT", "SESSION", "MOSTLY"],
      sessions.map { row in
        [
          Format.cpuTime(row.cpuSeconds), memory(row.peakResidentBytes), row.project, row.title,
          row.byKind.first.flatMap { ProcessKind(rawValue: $0.kind)?.label } ?? "-",
        ]
      })
    return table + "\n\n\(Format.cpuTime(cpuSeconds)) of CPU time in the last \(days) days."
  }
}
