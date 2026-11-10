import AAMCore
import AAMPlatform
import ArgumentParser

struct Stale: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "List what is no longer needed and why.",
    discussion: """
      Idle dev servers are judged only while the Agent Activity Monitor app is running, \
      because that takes watching CPU use over time.
      """
  )

  @OptionGroup var output: OutputOptions

  func run() throws {
    let look = Monitor.system().look()
    let now = look.observation.snapshot.takenAt
    let findings = StalenessRules().findings(
      in: look.observation.inventory, memory: look.memory, now: now)
    let report = StaleReport(takenAt: now, findings: findings, memory: look.memory)
    if output.json {
      try printJSON(report)
    } else {
      print(report.text(now: now))
    }
  }
}
