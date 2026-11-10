import AAMCore
import AAMPlatform
import Foundation
import Testing

/// Runs the built `aam` against the machine the tests run on. Everything it does to the machine
/// is read-only, and what it remembers goes to a scratch store.
@Suite(.timeLimit(.minutes(1)))
struct CommandLineTests {
  let scratch: TemporaryDirectory
  var store: URL { scratch.url.appendingPathComponent("aam.sqlite") }

  init() throws {
    scratch = try TemporaryDirectory()
  }

  func run(_ arguments: String...) throws -> (status: Int32, output: Data) {
    try run(arguments)
  }

  func run(_ arguments: [String]) throws -> (status: Int32, output: Data) {
    let aam = Process()
    aam.executableURL = Helper.url.deletingLastPathComponent().appendingPathComponent("aam")
    aam.arguments = arguments
    aam.environment = ["AAM_STORE": store.path, "HOME": NSHomeDirectory()]
    let output = Pipe()
    aam.standardOutput = output
    aam.standardError = FileHandle.nullDevice
    try aam.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    aam.waitUntilExit()
    return (aam.terminationStatus, data)
  }

  func json(_ arguments: String...) throws -> [String: Any] {
    let result = try run(arguments)
    #expect(result.status == 0)
    return try #require(JSONSerialization.jsonObject(with: result.output) as? [String: Any])
  }

  @Test func `the version is printed`() throws {
    let result = try run("--version")

    #expect(result.status == 0)
    #expect(String(decoding: result.output, as: UTF8.self).split(separator: ".").count == 3)
  }

  @Test func `sessions are reported as JSON`() throws {
    let report = try json("sessions", "--json")

    #expect(report["takenAt"] is String)
    #expect(report["sessions"] is [Any])
  }

  @Test func `processes are reported as JSON grouped by Project`() throws {
    let report = try json("ps", "--json")

    #expect(report["projects"] is [Any])
    #expect(report["unattributedCount"] is Int)
  }

  @Test func `Culprits are reported as JSON after a short measurement`() throws {
    let report = try json("culprits", "--json", "--interval", "0.2")

    #expect(report["culprits"] is [Any])
    #expect(report["intervalSeconds"] as? Double == 0.2)
  }

  @Test func `what is Stale is reported as JSON`() throws {
    let report = try json("stale", "--json")

    #expect(report["findings"] is [Any])
    #expect(report["reclaimableBytes"] is Int)
    #expect(report["activityObserved"] is Bool)
  }

  @Test func `the human-readable Session list starts with its header`() throws {
    let result = try run("sessions")

    #expect(result.status == 0)
    #expect(String(decoding: result.output, as: UTF8.self).hasPrefix("PROJECT"))
  }

  @Test func `what a look remembers is kept where AAM_STORE points`() throws {
    _ = try run("sessions", "--json")

    #expect(FileManager.default.fileExists(atPath: store.path))
  }

  // MARK: Cleanup requests

  @Test func `a Cleanup request is filed for a person to decide and nothing is ended`() throws {
    let helper = try Helper.sleeping(seconds: 30)
    defer { helper.terminate() }
    let pid = helper.processIdentifier

    let filed = try json("request-cleanup", String(pid), "--reason", "left by my tests", "--json")

    #expect(filed["status"] as? String == "pending")
    #expect(filed["pids"] as? [Int] == [Int(pid)])
    let stored = try #require(try Store(url: store).requests(status: .pending).first)
    #expect(stored.id == filed["id"] as? String)
    #expect(stored.reason == "left by my tests")
    #expect(stored.targets.map(\.pid) == [pid])
    #expect(helper.isRunning)

    let listed = try json("requests", "--json")
    let rows = try #require(listed["requests"] as? [[String: Any]])
    #expect(rows.map { $0["id"] as? String } == [stored.id])
  }

  @Test func `a Cleanup request for a process that may not be ended is not filed`() throws {
    let result = try run("request-cleanup", "1", "--json")

    #expect(result.status == 1)
    #expect((try? Store(url: store).requests())?.isEmpty != false)
  }

  @Test func `a Cleanup request for a process that does not exist is not filed`() throws {
    let helper = try Helper.sleeping(seconds: 0)
    helper.waitUntilExit()

    #expect(try run("request-cleanup", String(helper.processIdentifier)).status == 1)
  }

  @Test func `a decided Cleanup request shows what was decided`() throws {
    var request = CleanupRequest(
      id: "abc12345", createdAt: Date(), requester: nil, reason: "x", targets: [])
    request.status = .done
    request.decidedAt = Date()
    request.outcome = CleanupRequest.Outcome(ended: 3, killed: 0, survived: 0, refused: 0)
    let connection = try Store(url: store)
    try connection.add(request)
    try connection.update(request)

    let rows = try #require(try json("requests", "--json")["requests"] as? [[String: Any]])

    #expect(rows.first?["status"] as? String == "done")
    #expect((rows.first?["outcome"] as? [String: Any])?["ended"] as? Int == 3)
    let table = String(decoding: try run("requests").output, as: UTF8.self)
    #expect(table.contains("OUTCOME"))
    #expect(table.contains("3 exited."))
  }

  // MARK: Reports

  @Test func `where CPU time went is reported from what the store holds`() throws {
    let session = SessionID(harness: .claudeCode, value: "s1")
    let alpha = Project(root: "/work/alpha")
    let connection = try Store(url: store)
    var memory = Memory.empty
    memory.sessions[session] = Memory.PastSession(
      project: alpha, title: "Fix login", markers: [:], lastSeenAt: Date(), endedAt: nil)
    try connection.save(memory)
    try connection.record([
      HistoryBucket(
        minute: Date().addingTimeInterval(-3600), project: alpha, session: session,
        kind: .testRunner, cpuSeconds: 150, peakResidentBytes: 2_097_152),
      HistoryBucket(
        minute: Date().addingTimeInterval(-3 * 86_400), project: alpha, session: session,
        kind: .testRunner, cpuSeconds: 9000, peakResidentBytes: 0),
    ])

    let report = try json("report", "--days", "1", "--json")
    let table = String(decoding: try run("report", "--days", "1").output, as: UTF8.self)

    #expect(report["cpuSeconds"] as? Double == 150)
    #expect(report["days"] as? Int == 1)
    let rows = try #require(report["sessions"] as? [[String: Any]])
    #expect(rows.map { $0["title"] as? String } == ["Fix login"])
    #expect(rows.first?["project"] as? String == "alpha")
    #expect(rows.first?["peakResidentBytes"] as? Int == 2_097_152)
    #expect(table.contains("CPU TIME"))
    #expect(table.contains("Fix login"))
    #expect(table.contains("2m"))
  }

  @Test(arguments: ["0", "31", "many"])
  func `a report is refused for a period it cannot cover`(days: String) throws {
    #expect(try run("report", "--days", days).status != 0)
  }

  // MARK: Model Context Protocol

  /// Starts `aam mcp`, sends the messages one per line and returns the replies.
  func converse(_ messages: [String]) throws -> [JSONValue] {
    let aam = Process()
    aam.executableURL = Helper.url.deletingLastPathComponent().appendingPathComponent("aam")
    aam.arguments = ["mcp"]
    aam.environment = ["AAM_STORE": store.path, "HOME": NSHomeDirectory()]
    let input = Pipe()
    let output = Pipe()
    aam.standardInput = input
    aam.standardOutput = output
    aam.standardError = FileHandle.nullDevice
    try aam.run()
    input.fileHandleForWriting.write(Data((messages.joined(separator: "\n") + "\n").utf8))
    try input.fileHandleForWriting.close()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    aam.waitUntilExit()
    #expect(aam.terminationStatus == 0)
    return try data.split(separator: UInt8(ascii: "\n")).map {
      try JSONDecoder().decode(JSONValue.self, from: Data($0))
    }
  }

  /// The JSON a tool call answered with.
  func toolResult(_ reply: JSONValue) throws -> JSONValue {
    let text = try #require(reply["result"]?["content"]?.array?.first?["text"]?.string)
    return try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
  }

  @Test func `an agent can connect over stdio, list the tools and read the Sessions`() throws {
    let replies = try converse([
      #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"0"}}}"#,
      #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
      #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#,
      #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_sessions","arguments":{}}}"#,
    ])

    #expect(replies.count == 3)
    #expect(replies[0]["result"]?["serverInfo"]?["name"] == .string("agent-activity-monitor"))
    let tools = try #require(replies[1]["result"]?["tools"]?.array).compactMap {
      $0["name"]?.string
    }
    #expect(
      tools == [
        "list_sessions", "my_session", "list_culprits", "list_stale", "request_cleanup",
        "get_request",
      ])
    #expect(replies[2]["result"]?["isError"] == .bool(false))
    #expect(try toolResult(replies[2])["sessions"]?.array != nil)
  }

  @Test func `an agent can ask for a Cleanup and nothing is ended by asking`() throws {
    let helper = try Helper.sleeping(seconds: 30)
    defer { helper.terminate() }
    let pid = helper.processIdentifier

    let filed = try toolResult(
      try #require(
        converse([
          #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"request_cleanup","arguments":{"pids":[\#(pid)],"reason":"left by my tests"}}}"#
        ]).first))
    let id = try #require(filed["id"]?.string)
    let read = try toolResult(
      try #require(
        converse([
          #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_request","arguments":{"id":"\#(id)"}}}"#
        ]).first))

    #expect(filed["status"] == JSONValue.string("pending"))
    #expect(read["status"] == JSONValue.string("pending"))
    #expect(read["reason"] == JSONValue.string("left by my tests"))
    #expect(try Store(url: store).requests(status: .pending).map(\.id) == [id])
    #expect(helper.isRunning)
  }

  @Test func `a tool that is given nonsense says so instead of failing the connection`() throws {
    let replies = try converse([
      #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"request_cleanup","arguments":{"pids":["all of them"]}}}"#,
      #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_request","arguments":{"id":"nope"}}}"#,
    ])

    #expect(replies.map { $0["result"]?["isError"] } == [.bool(true), .bool(true)])
    #expect((try? Store(url: store).requests())?.isEmpty != false)
  }
}
