import AAMCore
import AAMPlatform
import Foundation
import Testing

/// Runs the built `aam` against the machine the tests run on. Everything it does to the machine
/// is read-only, and what it remembers goes to a scratch store.
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
  }
}
