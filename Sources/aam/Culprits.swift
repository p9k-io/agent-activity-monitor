import AAMCore
import AAMPlatform
import ArgumentParser
import Foundation

struct Culprits: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Rank what is consuming CPU right now and say whom it belongs to.")

  @OptionGroup var output: OutputOptions

  @Option(name: .long, help: "Seconds to measure CPU use over.")
  var interval: Double = 1.0

  @Option(name: .long, help: "CPU use, in percent of one core, from which something is listed.")
  var threshold: Double = 25

  func validate() throws {
    guard interval > 0 else {
      throw ValidationError("--interval must be greater than zero.")
    }
  }

  func run() throws {
    let observer = Observer.system()
    let before = observer.observe()
    Thread.sleep(forTimeInterval: interval)
    let after = observer.observe()
    let culprits = CulpritRanker(threshold: threshold).culprits(
      in: after.inventory,
      usage: Usage(previous: before.snapshot, current: after.snapshot)
    )
    let report = CulpritsReport(
      takenAt: after.snapshot.takenAt, intervalSeconds: interval, culprits: culprits)
    if output.json {
      try printJSON(report)
    } else {
      print(report.table)
    }
  }
}
