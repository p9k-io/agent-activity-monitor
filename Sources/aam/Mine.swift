import AAMCore
import AAMPlatform
import ArgumentParser
import Foundation

struct Mine: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Show the Session this command runs in and what is attributed to it.",
    discussion: "The Session is found from the process tree, not from anything the caller says."
  )

  @OptionGroup var output: OutputOptions

  func run() throws {
    let observation = Observer.system().observe()
    guard let group = observation.inventory.session(owning: getpid()) else {
      FileHandle.standardError.write(Data("aam: this command is not running in a Session.\n".utf8))
      throw ExitCode(1)
    }
    let report = MineReport(takenAt: observation.snapshot.takenAt, group: group)
    if output.json {
      try printJSON(report)
    } else {
      print(report.text(now: observation.snapshot.takenAt))
    }
  }
}
