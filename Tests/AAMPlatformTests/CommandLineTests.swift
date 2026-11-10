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
}
