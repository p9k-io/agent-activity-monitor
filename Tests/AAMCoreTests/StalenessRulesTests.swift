import AAMCore
import Foundation
import Testing

struct StalenessRulesTests {
  /// The moment the rules are asked. Everything else is placed relative to it.
  let now = epoch.addingTimeInterval(500 * 3600)
  let alpha = Project(root: "/work/alpha")
  let root = ProcessRecord.make(100, path: "/opt/bin/claude", rss: 400, terminal: true)

  func ago(hours: Double = 0, minutes: Double = 0) -> Date {
    now.addingTimeInterval(-(hours * 3600 + minutes * 60))
  }

  func session(
    _ state: SessionState, active: Date?, root: ProcessRecord? = nil, id: String = "s1"
  ) -> Session {
    Session.make(
      id, root: root ?? self.root, project: alpha.root, title: "Fix login", state: state,
      lastActivity: active, markers: ["ID": id])
  }

  func findings(
    _ processes: [ProcessRecord], sessions: [Session] = [], memory: Memory = .empty
  ) -> [StaleFinding] {
    let inventory = Attributor().inventory(
      of: Snapshot(takenAt: now, processes: processes), sessions: sessions, memory: memory)
    return StalenessRules().findings(in: inventory, memory: memory, now: now)
  }

  /// Memory of a Session in Project alpha that ended at `endedAt`.
  func memory(endedAt: Date, id: String = "gone") -> Memory {
    var memory = Memory.empty
    memory.sessions[SessionID(harness: .claudeCode, value: id)] = Memory.PastSession(
      project: alpha, title: nil, markers: ["ID": id], lastSeenAt: endedAt, endedAt: endedAt)
    return memory
  }

  // MARK: Idle session

  @Test func `a Session with no activity for longer than a day is an Idle session`() throws {
    let child = ProcessRecord.make(101, parent: 100, path: "/opt/bin/node", rss: 600)
    let idle = session(.idle, active: ago(hours: 25))

    let finding = try #require(findings([root, child], sessions: [idle]).first)

    #expect(finding.kind == .idleSession)
    #expect(finding.reason == .sessionIdle(since: ago(hours: 25)))
    #expect(finding.session == idle.id)
    #expect(finding.project == alpha)
    #expect(finding.title == "Fix login")
    #expect(finding.processes.map(\.pid) == [100, 101])
    #expect(finding.residentBytes == 1000)
    #expect(finding.canCleanUp)
  }

  @Test(arguments: [SessionState.idle, .waiting, .background])
  func `any Session that is not working can be idle`(state: SessionState) {
    #expect(findings([root], sessions: [session(state, active: ago(hours: 30))]).count == 1)
  }

  @Test func `a working Session is never stale, however long its turn has run`() {
    #expect(findings([root], sessions: [session(.working, active: ago(hours: 90))]).isEmpty)
  }

  @Test func `a Session active within the last day is not idle yet`() {
    #expect(findings([root], sessions: [session(.idle, active: ago(hours: 23))]).isEmpty)
  }

  @Test(arguments: [
    (SessionState.unknown, Optional(Date(timeIntervalSince1970: 0))),
    (.idle, nil),
  ])
  func `a Session whose state or last activity is not known is not judged`(
    state: SessionState, active: Date?
  ) {
    #expect(findings([root], sessions: [session(state, active: active)]).isEmpty)
  }

  // MARK: Ownerless leftover

  @Test func `what a Session left behind is an Ownerless leftover two minutes after it ended`()
    throws
  {
    let survivor = ProcessRecord.make(
      300, path: "/opt/bin/node", arguments: ["npm", "exec", "some-mcp"], rss: 50,
      markers: ["ID": "gone"])
    let child = ProcessRecord.make(301, parent: 300, path: "/opt/bin/node", rss: 70)
    let memory = memory(endedAt: ago(minutes: 3))

    let finding = try #require(findings([survivor, child], memory: memory).first)

    #expect(finding.kind == .ownerlessLeftover)
    #expect(
      finding.reason
        == .orphan(
          formerSession: SessionID(harness: .claudeCode, value: "gone"),
          since: ago(minutes: 3)))
    #expect(finding.project == alpha)
    #expect(finding.processes.map(\.pid) == [300, 301])
    #expect(finding.residentBytes == 120)
  }

  @Test func `a Session that ended a moment ago may still be closing down`() {
    let survivor = ProcessRecord.make(300, path: "/opt/bin/node", markers: ["ID": "gone"])

    #expect(findings([survivor], memory: memory(endedAt: ago(minutes: 1))).isEmpty)
  }

  @Test func `an Orphan of a Session nobody saw is judged by its own age`() throws {
    let old = ProcessRecord.make(
      300, path: "/opt/bin/node", cwd: "/work/beta", startedAfter: 0, markers: ["ID": "never"])

    let finding = try #require(findings([old]).first)

    #expect(finding.kind == .ownerlessLeftover)
    #expect(finding.reason == .orphan(formerSession: nil, since: nil))
    #expect(finding.project == Project(root: "/work/beta"))
  }

  @Test func `a zombie in a Session tree is reported but cannot be cleaned up`() throws {
    let zombie = ProcessRecord.make(105, parent: 100, path: "node", zombie: true)

    let finding = try #require(
      findings([root, zombie], sessions: [session(.working, active: now)]).first)

    #expect(finding.kind == .ownerlessLeftover)
    #expect(finding.reason == .zombie(parent: 100))
    #expect(finding.processes.map(\.pid) == [105])
    #expect(!finding.canCleanUp)
  }

  @Test func `older copies of the same MCP server in one Session are Ownerless leftovers`() throws {
    func server(_ pid: Int32, after seconds: TimeInterval) -> ProcessRecord {
      .make(
        pid, parent: 100, path: "/opt/bin/node", arguments: ["npm", "exec", "some-mcp"], rss: 10,
        startedAfter: seconds)
    }
    let helper = ProcessRecord.make(211, parent: 210, path: "/opt/bin/node", rss: 5)
    let other = ProcessRecord.make(
      240, parent: 100, path: "/opt/bin/node", arguments: ["npm", "exec", "another-mcp"])

    let result = findings(
      [
        root, server(210, after: 10), helper, server(220, after: 20), server(230, after: 30), other,
      ],
      sessions: [session(.working, active: now)])

    let finding = try #require(result.first)
    #expect(result.count == 1)
    #expect(finding.kind == .ownerlessLeftover)
    #expect(finding.reason == .olderDuplicate(of: 230))
    #expect(finding.processes.map(\.pid) == [210, 211, 220])
    #expect(finding.residentBytes == 25)
  }

  @Test func `two copies of something that is not a server are not duplicates`() {
    let first = ProcessRecord.make(210, parent: 100, path: "/bin/sleep", arguments: ["sleep", "9"])
    let second = ProcessRecord.make(
      220, parent: 100, path: "/bin/sleep", arguments: ["sleep", "9"])

    #expect(
      findings([root, first, second], sessions: [session(.working, active: now)]).isEmpty)
  }

  // MARK: Forgotten induced load

  let simulator = ProcessRecord.make(
    700, path: "/Library/Developer/CoreSimulator/Volumes/x/usr/libexec/backboardd",
    cwd: "/work/alpha", rss: 900)

  @Test func `induced load in a Project where nothing worked for two hours is forgotten`() throws {
    let quiet = session(.idle, active: ago(hours: 3))

    let finding = try #require(findings([root, simulator], sessions: [quiet]).first)

    #expect(finding.kind == .forgottenInducedLoad)
    #expect(finding.reason == .projectQuiet(since: ago(hours: 3)))
    #expect(finding.project == alpha)
    #expect(finding.session == nil)
    #expect(finding.processes.map(\.pid) == [700])
  }

  @Test(arguments: [
    (SessionState.working, 30.0),
    (.idle, 1.0),
  ])
  func `induced load is not forgotten while its Project is in use`(
    state: SessionState, hours: Double
  ) {
    let busy = session(state, active: ago(hours: hours))

    #expect(findings([root, simulator], sessions: [busy]).isEmpty)
  }

  @Test func `induced load of a Project whose last Session ended hours ago is forgotten`() throws {
    let finding = try #require(
      findings([simulator], memory: memory(endedAt: ago(hours: 5))).first)

    #expect(finding.kind == .forgottenInducedLoad)
    #expect(finding.reason == .projectQuiet(since: ago(hours: 5)))
  }

  // MARK: Idle dev server

  let server = ProcessRecord.make(
    800, parent: 100, path: "/opt/bin/node", arguments: ["node", "scripts/dev.mjs"], rss: 300)

  func busy(_ process: ProcessRecord, at date: Date, in memory: Memory = .empty) -> Memory {
    var memory = memory
    memory.lastBusyAt[process.key] = date
    memory.activityAsOf = now
    return memory
  }

  @Test func `a dev server that did nothing for two hours in an idle Session is stale`() throws {
    let worker = ProcessRecord.make(801, parent: 800, path: "/opt/bin/esbuild", rss: 40)
    let memory = busy(server, at: ago(hours: 3))

    let finding = try #require(
      findings(
        [root, server, worker], sessions: [session(.background, active: ago(hours: 5))],
        memory: memory
      ).first)

    #expect(finding.kind == .idleDevServer)
    #expect(finding.reason == .serverIdle(since: ago(hours: 3)))
    #expect(finding.session?.value == "s1")
    #expect(finding.processes.map(\.pid) == [800, 801])
    #expect(finding.residentBytes == 340)
  }

  @Test func `a dev server in a working Session is in use`() {
    let memory = busy(server, at: ago(hours: 3))

    #expect(
      findings([root, server], sessions: [session(.working, active: now)], memory: memory).isEmpty)
  }

  @Test func `a dev server that was busy within two hours is in use`() {
    let memory = busy(server, at: ago(hours: 1))

    #expect(
      findings([root, server], sessions: [session(.idle, active: ago(hours: 5))], memory: memory)
        .isEmpty)
  }

  @Test func `a dev server is not judged once its activity is no longer being observed`() {
    var memory = busy(server, at: ago(hours: 3))
    memory.activityAsOf = ago(minutes: 10)

    #expect(
      findings([root, server], sessions: [session(.idle, active: ago(hours: 5))], memory: memory)
        .isEmpty)
  }

  @Test func `a dev server whose activity was never observed is not judged`() {
    #expect(findings([root, server], sessions: [session(.idle, active: ago(hours: 5))]).isEmpty)
  }

  @Test func `a dev server left by an ended Session but still being used is not stale`() {
    let orphaned = ProcessRecord.make(
      800, path: "/opt/bin/node", arguments: ["node", "scripts/dev.mjs"], markers: ["ID": "gone"])
    let memory = busy(orphaned, at: ago(minutes: 10), in: memory(endedAt: ago(hours: 6)))

    #expect(findings([orphaned], memory: memory).isEmpty)
  }

  @Test func `a dev server left by an ended Session and idle since is an Idle dev server`() throws {
    let orphaned = ProcessRecord.make(
      800, path: "/opt/bin/node", arguments: ["node", "scripts/dev.mjs"], markers: ["ID": "gone"])
    let memory = busy(orphaned, at: ago(hours: 4), in: memory(endedAt: ago(hours: 6)))

    let result = findings([orphaned], memory: memory)

    #expect(result.map(\.kind) == [.idleDevServer])
    #expect(result.first?.reason == .serverIdle(since: ago(hours: 4)))
  }

  // MARK: Order

  @Test func `findings are listed from the one that frees the most memory`() {
    let small = ProcessRecord.make(100, path: "/opt/bin/claude", rss: 10, terminal: true)
    let big = ProcessRecord.make(200, path: "/opt/bin/codex", rss: 900, terminal: true)

    let result = findings(
      [small, big],
      sessions: [
        session(.idle, active: ago(hours: 30), root: small, id: "small"),
        session(.idle, active: ago(hours: 30), root: big, id: "big"),
      ])

    #expect(result.map(\.session?.value) == ["big", "small"])
  }
}
