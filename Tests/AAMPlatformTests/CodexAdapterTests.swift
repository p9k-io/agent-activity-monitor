import AAMCore
import AAMPlatform
import Foundation
import Testing

struct CodexAdapterTests {
  let home: TemporaryDirectory
  let codex = ProcessRecord.make(5100, path: "/opt/tools/bin/codex", arguments: ["codex"])
  let thread = "22222222-aaaa-7bbb-8ccc-000000000001"

  init() throws {
    home = try TemporaryDirectory()
  }

  func adapter(open: [Int32: [String]] = [:]) -> CodexAdapter {
    CodexAdapter(
      home: home.url, projects: DirectoryIsProject(), openFiles: DeclaredOpenFiles(byPID: open))
  }

  /// Writes a synthetic rollout file and returns its path.
  func rollout(
    _ id: String,
    startedAt stamp: String = "2026-01-05T08-00-00",
    events: [String]
  ) throws -> String {
    let meta =
      "{\"timestamp\":\"2026-01-05T08:00:00.000Z\",\"type\":\"session_meta\",\"payload\":{}}"
    return try home.file(
      ".codex/sessions/2026/01/05/rollout-\(stamp)-\(id).jsonl",
      ([meta] + events).joined(separator: "\n") + "\n"
    ).path
  }

  func event(_ type: String, at time: String) -> String {
    "{\"timestamp\":\"2026-01-05T\(time).000Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"\(type)\"}}"
  }

  @Test func `a Codex process with an open rollout is a Session of that thread`() throws {
    let path = try rollout(thread, events: [event("task_started", at: "08:01:00")])
    try home.file(
      ".codex/session_index.jsonl",
      "{\"id\":\"\(thread)\",\"thread_name\":\"Tidy the importer\",\"updated_at\":\"x\"}\n")

    let session = try #require(adapter(open: [5100: [path]]).sessions(in: .of(codex)).first)

    #expect(session.id == SessionID(harness: .codex, value: thread))
    #expect(session.root == codex.key)
    #expect(session.project == Project(root: "/work/alpha"))
    #expect(session.title == "Tidy the importer")
    #expect(session.state == .working)
    #expect(session.resumeCommand == "codex resume \(thread)")
  }

  @Test(arguments: [
    (["task_started", "task_complete"], SessionState.idle),
    (["task_started", "turn_aborted"], .idle),
    (["task_started", "task_complete", "task_started"], .working),
    (["token_count"], .unknown),
  ])
  func `the last turn event decides the state`(events: [String], expected: SessionState) throws {
    let lines = events.enumerated().map { event($1, at: "08:0\($0 + 1):00") }
    let path = try rollout(thread, events: lines)

    #expect(adapter(open: [5100: [path]]).sessions(in: .of(codex)).first?.state == expected)
  }

  @Test func `the last line's time is the last activity`() throws {
    let path = try rollout(
      thread,
      events: [event("task_started", at: "08:01:00"), event("task_complete", at: "08:05:30")])
    let expected = try Date("2026-01-05T08:05:30Z", strategy: .iso8601)

    let session = try #require(adapter(open: [5100: [path]]).sessions(in: .of(codex)).first)

    #expect(session.lastActivityAt == expected)
  }

  /// A line of the kind a long turn writes by the thousand: tool output, far larger than a turn
  /// event and not one.
  func toolOutput(_ text: String, at time: String = "08:02:00") -> String {
    "{\"timestamp\":\"2026-01-05T\(time).000Z\",\"type\":\"response_item\","
      + "\"payload\":{\"type\":\"custom_tool_call_output\",\"output\":\"\(text)\"}}"
  }

  @Test func `a turn that has been running for megabytes of output is still working`() throws {
    let filler = toolOutput(String(repeating: "x", count: 1000))
    let path = try rollout(
      thread,
      events: [event("task_started", at: "08:01:00")] + Array(repeating: filler, count: 6000))

    #expect(adapter(open: [5100: [path]]).sessions(in: .of(codex)).first?.state == .working)
  }

  @Test func `tool output that merely quotes a turn event does not end the turn`() throws {
    let quoting = toolOutput("see {\\\"type\\\":\\\"task_complete\\\"} in the fixture")
    let path = try rollout(thread, events: [event("task_started", at: "08:01:00"), quoting])

    #expect(adapter(open: [5100: [path]]).sessions(in: .of(codex)).first?.state == .working)
  }

  @Test func `with several rollouts open, the one started first is the Session's own thread`()
    throws
  {
    let helper = "33333333-aaaa-7bbb-8ccc-000000000002"
    let main = try rollout(thread, startedAt: "2026-01-05T08-00-00", events: [])
    let spawned = try rollout(helper, startedAt: "2026-01-05T08-30-00", events: [])

    let session = try #require(
      adapter(open: [5100: [spawned, main]]).sessions(in: .of(codex)).first)

    #expect(session.id.value == thread)
  }

  @Test func `a resumed thread is found on disk when its rollout is not open`() throws {
    _ = try rollout(thread, events: [event("task_complete", at: "08:02:00")])
    let resumed = ProcessRecord.make(
      5100, path: "/opt/tools/bin/codex", arguments: ["codex", "resume", thread])

    let session = try #require(adapter().sessions(in: .of(resumed)).first)

    #expect(session.id.value == thread)
    #expect(session.state == .idle)
  }

  @Test func `a Codex process without a thread and without a terminal is not a Session`() {
    let daemon = ProcessRecord.make(
      5200, path: "/opt/tools/bin/codex", arguments: ["codex", "app-server"], terminal: false)

    #expect(adapter().sessions(in: .of(daemon)).isEmpty)
  }

  @Test func `a Codex process on a terminal without a thread is a Session in unknown state`()
    throws
  {
    let session = try #require(adapter().sessions(in: .of(codex)).first)

    #expect(session.id == SessionID(harness: .codex, value: "pid-5100"))
    #expect(session.state == .unknown)
    #expect(session.resumeCommand == nil)
  }

  @Test func `a helper started by a Codex Session is not a Session of its own`() throws {
    let path = try rollout(thread, events: [])
    let helper = ProcessRecord.make(
      5300, parent: 5100, path: "/opt/tools/bin/codex", arguments: ["codex", "sandbox"])

    let sessions = adapter(open: [5100: [path]]).sessions(in: .of(codex, helper))

    #expect(sessions.map(\.root.pid) == [5100])
  }

  @Test func `a rollout that cannot be read degrades to unknown instead of failing`() throws {
    let path = try home.file(
      ".codex/sessions/2026/01/05/rollout-2026-01-05T08-00-00-\(thread).jsonl",
      "not json at all\n{\"half\": \n"
    ).path

    let session = try #require(adapter(open: [5100: [path]]).sessions(in: .of(codex)).first)

    #expect(session.id.value == thread)
    #expect(session.state == .unknown)
    #expect(session.lastActivityAt == nil)
  }
}

struct LibprocOpenFilesTests {
  @Test func `a file the current process holds open is listed`() throws {
    let scratch = try TemporaryDirectory()
    let file = try scratch.file("held-open.txt", "x")
    let handle = try FileHandle(forReadingFrom: file)
    defer { try? handle.close() }

    #expect(LibprocOpenFiles().openFiles(of: getpid()).contains(file.path))
  }

  @Test func `a process that does not exist has no open files`() throws {
    let child = try Helper.sleeping(seconds: 0)
    child.waitUntilExit()

    #expect(LibprocOpenFiles().openFiles(of: child.processIdentifier).isEmpty)
  }
}
