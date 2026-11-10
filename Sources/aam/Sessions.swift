import AAMCore
import AAMPlatform
import ArgumentParser

struct Sessions: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "List the running Sessions with their Project, state and memory.")

  @OptionGroup var output: OutputOptions

  func run() throws {
    let observation = Observer.system().observe()
    let report = SessionsReport(observation)
    if output.json {
      try printJSON(report)
    } else {
      print(report.table(now: observation.snapshot.takenAt))
    }
  }
}
