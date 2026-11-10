import AAMCore
import AAMPlatform
import ArgumentParser
import Foundation

struct MCP: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "mcp",
    abstract: "Serve the same facts to an agent over the Model Context Protocol (stdio).",
    discussion: """
      Started by a Harness, not by hand. The tools read, and one of them files a Cleanup \
      request. Nothing is ended: a person decides about a request in the app.
      """
  )

  func run() {
    MCPServer(
      name: "agent-activity-monitor", version: AAM.version,
      instructions: """
        Shows which processes exist because of AI coding agent sessions on this Mac, what \
        uses CPU right now and what is no longer needed. You cannot end a process with it. \
        When something you started is no longer needed, call request_cleanup with its \
        process identifiers: a person approves or denies the request in the Agent Activity \
        Monitor app, and get_request tells you what was decided.
        """,
      tools: MCPTools.all
    ).run()
  }
}

/// The tools `aam mcp` offers. Each one answers with the JSON the matching command prints.
enum MCPTools {
  struct Failure: Error, CustomStringConvertible {
    let description: String
  }

  static let all: [MCPTool] = [
    tool(
      "list_sessions",
      "List the AI coding agent Sessions running on this Mac, with Project, state, last "
        + "activity, memory and the command that resumes each."
    ) { _ in
      try json(SessionsReport(Monitor.system().look().observation))
    },
    tool(
      "my_session",
      "Show the Session this server runs in and every process attributed to it. The Session "
        + "is found from the process tree."
    ) { _ in
      let observation = Monitor.system().look().observation
      guard let group = observation.inventory.session(owning: getpid()) else {
        throw Failure(description: "This server is not running in a Session.")
      }
      return try json(MineReport(takenAt: observation.snapshot.takenAt, group: group))
    },
    tool(
      "list_culprits",
      "Rank what is using CPU right now and say which Session or Project it belongs to, "
        + "including load outside any Session such as simulators and browser content. "
        + "Measures for one second."
    ) { _ in
      let monitor = Monitor.system()
      let before = monitor.look()
      Thread.sleep(forTimeInterval: 1)
      let after = monitor.look(after: before.observation).observation
      let culprits = CulpritRanker().culprits(
        in: after.inventory,
        usage: Usage(previous: before.observation.snapshot, current: after.snapshot),
        inducedLoad: monitor.inducedLoad(in: after))
      return try json(
        CulpritsReport(takenAt: after.snapshot.takenAt, intervalSeconds: 1, culprits: culprits))
    },
    tool(
      "list_stale",
      "List what is no longer needed and why: idle Sessions, leftovers of Sessions that "
        + "ended, older copies of servers, idle dev servers, forgotten induced load."
    ) { _ in
      let look = Monitor.system().look()
      let now = look.observation.snapshot.takenAt
      let findings = StalenessRules().findings(
        in: look.observation.inventory, memory: look.memory, now: now)
      return try json(StaleReport(takenAt: now, findings: findings, memory: look.memory))
    },
    MCPTool(
      name: "request_cleanup",
      description: "Ask for processes to be cleaned up. Nothing is ended by this call: the "
        + "request waits in the Agent Activity Monitor app until a person approves or denies "
        + "it. What each process started is cleaned up with it. Ask only for what you "
        + "started and no longer need, and say why.",
      inputSchema: schema(
        [
          "pids": .object([
            "type": .string("array"), "items": .object(["type": .string("integer")]),
            "minItems": .integer(1),
            "description": .string("Identifiers of the processes that are no longer needed."),
          ]),
          "reason": .object([
            "type": .string("string"),
            "description": .string(
              "Why they are no longer needed. One line, shown to the person who decides."),
          ]),
        ], required: ["pids"])
    ) { arguments in
      let pids = (arguments["pids"]?.array ?? []).compactMap { value in
        value.integer.flatMap(Int32.init(exactly:))
      }
      guard !pids.isEmpty, pids.count == arguments["pids"]?.array?.count else {
        throw Failure(description: "pids must be a list of process identifiers.")
      }
      let store = try openStore()
      let reading = Monitor(store: store).look().observation
      let filed = try CleanupRequestFiler(store: store).file(
        pids: pids, reason: arguments["reason"]?.string ?? "", in: reading)
      return try json(RequestRow(filed.request, refused: filed.refused))
    },
    MCPTool(
      name: "get_request",
      description: "Tell what was decided about a Cleanup request: pending, done with what "
        + "the Cleanup did, or denied.",
      inputSchema: schema(
        [
          "id": .object([
            "type": .string("string"),
            "description": .string("The identifier request_cleanup returned."),
          ])
        ], required: ["id"])
    ) { arguments in
      guard let id = arguments["id"]?.string else {
        throw Failure(description: "id must be the identifier of a Cleanup request.")
      }
      guard let request = try openStore().requests().first(where: { $0.id == id }) else {
        throw Failure(description: "There is no Cleanup request \(id).")
      }
      return try json(RequestRow(request, refused: []))
    },
  ]

  /// A tool that takes no arguments.
  private static func tool(
    _ name: String, _ description: String, _ call: @escaping @Sendable (JSONValue) throws -> String
  ) -> MCPTool {
    MCPTool(name: name, description: description, inputSchema: schema([:]), call: call)
  }

  private static func schema(_ properties: [String: JSONValue], required: [String] = [])
    -> JSONValue
  {
    .object([
      "type": .string("object"), "properties": .object(properties),
      "required": .array(required.map(JSONValue.string)),
      "additionalProperties": .bool(false),
    ])
  }

  private static func openStore() throws -> Store {
    do {
      return try Store(url: Store.defaultURL)
    } catch {
      throw Failure(description: "The store at \(Store.defaultURL.path) cannot be opened.")
    }
  }

  private static func json(_ value: some Encodable) throws -> String {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
  }
}
