import Foundation
import Testing

/// Runs the built `aam` against the machine the tests run on. Everything it does is read-only.
struct CommandLineTests {
  func run(_ arguments: String...) throws -> (status: Int32, output: Data) {
    let aam = Process()
    aam.executableURL = Helper.url.deletingLastPathComponent().appendingPathComponent("aam")
    aam.arguments = arguments
    let output = Pipe()
    aam.standardOutput = output
    aam.standardError = FileHandle.nullDevice
    try aam.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    aam.waitUntilExit()
    return (aam.terminationStatus, data)
  }

  func json(_ arguments: String...) throws -> [String: Any] {
    let aam = Process()
    aam.executableURL = Helper.url.deletingLastPathComponent().appendingPathComponent("aam")
    aam.arguments = arguments
    let output = Pipe()
    aam.standardOutput = output
    aam.standardError = FileHandle.nullDevice
    try aam.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    aam.waitUntilExit()
    #expect(aam.terminationStatus == 0)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
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

  @Test func `the human-readable Session list starts with its header`() throws {
    let result = try run("sessions")

    #expect(result.status == 0)
    #expect(String(decoding: result.output, as: UTF8.self).hasPrefix("PROJECT"))
  }
}
