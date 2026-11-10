import AAMCore
import ArgumentParser

@main
struct AAMCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "aam",
    abstract: "Shows which processes exist because of AI coding agent sessions.",
    version: AAM.version
  )
}
