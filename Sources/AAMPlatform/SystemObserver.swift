import AAMCore
import Foundation

/// The process source and the Observer for this machine: every process, and the Sessions of
/// Claude Code and Codex CLI.
struct SystemParts {
  let source: SystemProcessSource
  let observer: Observer

  init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
    let projects = GitProjectResolver()
    let adapters: [any HarnessAdapter] = [
      ClaudeCodeAdapter(home: home, projects: projects),
      CodexAdapter(home: home, projects: projects),
    ]
    let markers = adapters.reduce(into: Set<String>()) { $0.formUnion($1.markerNames) }
    source = SystemProcessSource(markerNames: markers)
    observer = Observer(
      source: source, adapters: adapters,
      linkers: [SimulatorLinker(), WebContentLinker(), VirtualMachineLinker()],
      projects: projects)
  }
}

extension Observer {
  /// The Observer for this machine.
  public static func system(
    home: URL = FileManager.default.homeDirectoryForCurrentUser
  ) -> Observer {
    SystemParts(home: home).observer
  }
}
