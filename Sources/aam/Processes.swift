import AAMCore
import AAMPlatform
import ArgumentParser

struct Processes: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "ps",
    abstract: "List processes grouped by Project and Session, each with its Evidence.")

  @OptionGroup var output: OutputOptions

  @Flag(name: .long, help: "Also list the processes that belong to no Session.")
  var all = false

  func run() throws {
    let report = ProcessesReport(Observer.system().observe(), includeUnattributed: all)
    if output.json {
      try printJSON(report)
    } else {
      print(report.text)
    }
  }
}
