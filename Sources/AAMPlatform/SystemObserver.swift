import AAMCore
import Foundation

extension Observer {
  /// The Observer for this machine: every process, and the Sessions of Claude Code and Codex CLI.
  public static func system(
    home: URL = FileManager.default.homeDirectoryForCurrentUser
  ) -> Observer {
    let projects = GitProjectResolver()
    let adapters: [any HarnessAdapter] = [
      ClaudeCodeAdapter(home: home, projects: projects),
      CodexAdapter(home: home, projects: projects),
    ]
    let markers = adapters.reduce(into: Set<String>()) { $0.formUnion($1.markerNames) }
    return Observer(
      source: SystemProcessSource(markerNames: markers), adapters: adapters,
      linkers: [SimulatorLinker(), WebContentLinker()], projects: projects)
  }
}
