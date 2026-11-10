import AAMCore
import Darwin
import Foundation
import Synchronization

/// cmux as a Host: names the group of panels and the panel a Session's terminal is in, and
/// brings that panel to the front.
///
/// It reads two identifiers cmux puts into the environment of what it starts and asks cmux's
/// own command line tool for the names that go with them. When either is missing, the Session
/// keeps the place it had.
public final class CmuxHost: HostAdapter {
  /// The values of the named environment variables of a process.
  public typealias Environment = @Sendable (Int32, Set<String>) -> [String: String]
  /// Runs cmux's command line tool and returns what it printed, or nil when it failed.
  public typealias Runner = @Sendable ([String]) -> Data?

  private static let workspace = "CMUX_WORKSPACE_ID"
  private static let surface = "CMUX_SURFACE_ID"

  private struct Identifiers: Equatable {
    let workspace: String
    let surface: String
  }

  private struct State {
    /// What each Session's root process was found to carry; nil inside means nothing.
    var identifiers: [ProcessRecord.Key: Identifiers?] = [:]
    var workspaces: [String: String] = [:]
    var surfaces: [String: String] = [:]
    var askedAt: Date?
  }

  private let environment: Environment
  private let run: Runner
  private let now: @Sendable () -> Date
  /// The names change rarely and asking for them starts a process.
  private let refreshEvery: TimeInterval
  private let state = Mutex(State())

  public init(
    environment: @escaping Environment = CmuxHost.environment,
    run: @escaping Runner = CmuxHost.tool,
    now: @escaping @Sendable () -> Date = { Date() },
    refreshEvery: TimeInterval = 60
  ) {
    self.environment = environment
    self.run = run
    self.now = now
    self.refreshEvery = refreshEvery
  }

  public func refine(
    _ places: [SessionID: HostPlace], sessions: [Session]
  ) -> [SessionID: HostPlace] {
    state.withLock { state in
      // What a root process carries does not change while it lives, so it is read once.
      let roots = Set(sessions.map(\.root))
      state.identifiers = state.identifiers.filter { roots.contains($0.key) }
      for session in sessions where state.identifiers[session.root] == nil {
        let values = environment(session.root.pid, [Self.workspace, Self.surface])
        state.identifiers[session.root] = .some(
          values[Self.workspace].flatMap { workspace in
            values[Self.surface].map { Identifiers(workspace: workspace, surface: $0) }
          })
      }
      guard state.identifiers.values.contains(where: { $0 != nil }) else { return places }

      if state.askedAt.map({ now().timeIntervalSince($0) >= refreshEvery }) ?? true {
        state.askedAt = now()
        if let layout = run(["--json", "--id-format", "uuids", "tree", "--all"]) {
          (state.workspaces, state.surfaces) = Self.names(in: layout)
        }
      }

      var refined = places
      for session in sessions {
        guard let place = places[session.id],
          let found = state.identifiers[session.root] ?? nil,
          let workspace = state.workspaces[found.workspace]
        else { continue }
        let panel = state.surfaces[found.surface]
        refined[session.id] = HostPlace(
          host: place.host, hostPID: place.hostPID,
          location: [workspace, panel].compactMap(\.self).joined(separator: " › "),
          reference: ["workspace": found.workspace, "panel": found.surface])
      }
      return refined
    }
  }

  public func show(_ place: HostPlace) -> Bool {
    guard let workspace = place.reference["workspace"], let panel = place.reference["panel"]
    else { return false }
    let selected = run(["select-workspace", "--workspace", workspace]) != nil
    let focused = run(["focus-panel", "--panel", panel, "--workspace", workspace]) != nil
    return selected && focused
  }

  /// The titles of every group of panels and of every terminal in the layout cmux prints.
  /// A browser panel's title is an address and is left out.
  private static func names(in layout: Data) -> (
    workspaces: [String: String], surfaces: [String: String]
  ) {
    var workspaces: [String: String] = [:]
    var surfaces: [String: String] = [:]
    guard let root = try? JSONSerialization.jsonObject(with: layout) as? [String: Any],
      let windows = root["windows"] as? [[String: Any]]
    else { return (workspaces, surfaces) }
    for window in windows {
      for workspace in window["workspaces"] as? [[String: Any]] ?? [] {
        guard let id = workspace["id"] as? String, let title = workspace["title"] as? String
        else { continue }
        workspaces[id] = title
        for pane in workspace["panes"] as? [[String: Any]] ?? [] {
          for surface in pane["surfaces"] as? [[String: Any]] ?? []
          where surface["type"] as? String == "terminal" {
            if let id = surface["id"] as? String, let title = surface["title"] as? String {
              surfaces[id] = title
            }
          }
        }
      }
    }
    return (workspaces, surfaces)
  }

  // MARK: This machine

  /// Reads the named variables from the environment of a process. Nothing else of the
  /// environment is kept.
  public static func environment(of pid: Int32, names: Set<String>) -> [String: String] {
    var size = 0
    var name = [CTL_KERN, KERN_PROCARGS2, pid]
    guard sysctl(&name, 3, nil, &size, nil, 0) == 0, size > 0 else { return [:] }
    var buffer = [UInt8](repeating: 0, count: size)
    guard sysctl(&name, 3, &buffer, &size, nil, 0) == 0 else { return [:] }
    return ProcessArguments.parse(Array(buffer[..<size]), markerNames: names)?.markers ?? [:]
  }

  /// Where cmux keeps its command line tool.
  private static let tools = [
    "/Applications/cmux.app/Contents/Resources/bin/cmux",
    "/opt/homebrew/bin/cmux",
    "/usr/local/bin/cmux",
  ]

  public static func tool(_ arguments: [String]) -> Data? {
    guard let path = tools.first(where: FileManager.default.isExecutableFile(atPath:)) else {
      return nil
    }
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
    } catch {
      return nil
    }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return process.terminationStatus == 0 ? data : nil
  }
}
