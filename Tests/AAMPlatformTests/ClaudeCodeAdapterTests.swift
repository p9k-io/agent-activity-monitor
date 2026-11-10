import AAMCore
import AAMPlatform
import Foundation
import Testing

struct ClaudeCodeAdapterTests {
  let home: TemporaryDirectory
  let adapter: ClaudeCodeAdapter
  let claude = ProcessRecord.make(
    4100, path: "/Users/dev/.local/share/claude/versions/9.9.9", arguments: ["claude"])

  init() throws {
    home = try TemporaryDirectory()
    adapter = ClaudeCodeAdapter(home: home.url, projects: DirectoryIsProject())
  }

  /// Writes a synthetic record in the shape Claude Code keeps for each of its processes.
  func record(pid: Int32, _ fields: String) throws {
    try home.file(".claude/sessions/\(pid).json", "{\"pid\": \(pid), \(fields)}")
  }

  @Test func `a recorded Claude Code process is a Session with the Harness's own facts`() throws {
    try record(
      pid: 4100,
      """
      "sessionId": "11111111-aaaa-4bbb-8ccc-000000000001", "cwd": "/work/alpha",
      "name": "Fix the login form", "status": "busy", "statusUpdatedAt": 1800000060000
      """)

    let session = try #require(adapter.sessions(in: .of(claude)).first)

    #expect(
      session.id
        == SessionID(harness: .claudeCode, value: "11111111-aaaa-4bbb-8ccc-000000000001"))
    #expect(session.root == claude.key)
    #expect(session.project == Project(root: "/work/alpha"))
    #expect(session.title == "Fix the login form")
    #expect(session.state == .working)
    #expect(session.lastActivityAt == epoch.addingTimeInterval(60))
    #expect(session.resumeCommand == "claude --resume 11111111-aaaa-4bbb-8ccc-000000000001")
    #expect(
      session.markers == ["CLAUDE_CODE_SESSION_ID": "11111111-aaaa-4bbb-8ccc-000000000001"])
  }

  @Test(arguments: [
    ("busy", SessionState.working),
    ("waiting", .waiting),
    ("shell", .background),
    ("idle", .idle),
    ("a-status-from-the-future", .unknown),
  ])
  func `the Harness's status maps to a Session state`(status: String, expected: SessionState)
    throws
  {
    try record(
      pid: 4100, "\"sessionId\": \"s\", \"cwd\": \"/work/alpha\", \"status\": \"\(status)\"")

    #expect(adapter.sessions(in: .of(claude)).first?.state == expected)
  }

  @Test func `a process started as claude is recognised by its first argument`() throws {
    let renamed = ProcessRecord.make(
      4200, path: "/opt/tools/bin/some-wrapper", arguments: ["/opt/tools/bin/claude", "--resume"])
    try record(pid: 4200, "\"sessionId\": \"s\", \"cwd\": \"/work/alpha\", \"status\": \"idle\"")

    #expect(adapter.sessions(in: .of(renamed)).count == 1)
  }

  @Test func `a helper process without a record and without a terminal is not a Session`() {
    let helper = ProcessRecord.make(
      4300, path: "/Users/dev/.local/share/claude/versions/9.9.9",
      arguments: ["claude", "--some-helper-mode"], terminal: false)

    #expect(adapter.sessions(in: .of(helper)).isEmpty)
  }

  @Test func `a Claude Code process on a terminal without a record is a Session in unknown state`()
    throws
  {
    let session = try #require(adapter.sessions(in: .of(claude)).first)

    #expect(session.state == .unknown)
    #expect(session.id == SessionID(harness: .claudeCode, value: "pid-4100"))
    #expect(session.project == Project(root: "/work/alpha"))
    #expect(session.resumeCommand == nil)
    #expect(session.markers.isEmpty)
  }

  @Test func `a record that cannot be read degrades to unknown instead of failing`() throws {
    try home.file(".claude/sessions/4100.json", "{ this is not JSON")

    #expect(adapter.sessions(in: .of(claude)).first?.state == .unknown)
  }

  @Test func `a record with fields of an unexpected type keeps what it can read`() throws {
    try record(
      pid: 4100, "\"sessionId\": \"s\", \"cwd\": \"/work/alpha\", \"status\": 7, \"name\": [1, 2]")

    let session = try #require(adapter.sessions(in: .of(claude)).first)

    #expect(session.id.value == "s")
    #expect(session.state == .unknown)
    #expect(session.title == nil)
  }

  @Test func `a record written for another process is ignored`() throws {
    try home.file(
      ".claude/sessions/4100.json",
      "{\"pid\": 9999, \"sessionId\": \"other\", \"cwd\": \"/work/beta\", \"status\": \"idle\"}")

    #expect(adapter.sessions(in: .of(claude)).first?.id.value == "pid-4100")
  }

  @Test func `a leftover record does not turn an unrelated process into a Session`() throws {
    let node = ProcessRecord.make(4100, path: "/opt/bin/node", arguments: ["node", "server.js"])
    try record(pid: 4100, "\"sessionId\": \"s\", \"cwd\": \"/work/alpha\", \"status\": \"idle\"")

    #expect(adapter.sessions(in: .of(node)).isEmpty)
  }

  @Test func `a record that did not change is not read a second time`() throws {
    try record(pid: 4100, "\"sessionId\": \"s\", \"cwd\": \"/work/alpha\", \"status\": \"idle\"")
    #expect(adapter.sessions(in: .of(claude)).first?.state == .idle)
    let file = home.url.appendingPathComponent(".claude/sessions/4100.json").path
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file) }

    #expect(adapter.sessions(in: .of(claude)).first?.state == .idle)
  }

  @Test func `a record that changed is read again`() throws {
    try record(pid: 4100, "\"sessionId\": \"s\", \"cwd\": \"/work/alpha\", \"status\": \"idle\"")
    #expect(adapter.sessions(in: .of(claude)).first?.state == .idle)

    try record(
      pid: 4100, "\"sessionId\": \"s\", \"cwd\": \"/work/alpha\", \"status\": \"busy\", \"n\": 1")

    #expect(adapter.sessions(in: .of(claude)).first?.state == .working)
  }
}
