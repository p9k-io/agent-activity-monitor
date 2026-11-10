import AAMCore
import ArgumentParser

@main
struct AAMCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "aam",
    abstract: "Shows which processes exist because of AI coding agent sessions.",
    discussion: """
      aam only reads. It never ends a process: a Cleanup is carried out by the \
      Agent Activity Monitor app after a person confirms it.
      """,
    version: AAM.version,
    subcommands: [Sessions.self, Processes.self, Culprits.self, Stale.self, Mine.self]
  )
}

/// Options every reporting command shares.
struct OutputOptions: ParsableArguments {
  @Flag(name: .long, help: "Print JSON instead of a table.")
  var json = false
}
