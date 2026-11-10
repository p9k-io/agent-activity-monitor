import AAMCore
import Foundation
import Testing

/// What must not be claimed for a Project or a Session, because it may be a person's own work,
/// and what must not be taken for left behind while its Session lives.
struct AttributorGuardTests {
  let root = ProcessRecord.make(100, path: "/opt/bin/claude", terminal: true)
  let alpha = Project(root: "/work/alpha")
  var session: Session { Session.make("s1", root: root, project: "/work/alpha") }

  func inventory(
    _ processes: [ProcessRecord], sessions: [Session], memory: Memory = .empty,
    home: String? = nil
  ) -> Inventory {
    Attributor(home: home).inventory(
      of: Snapshot(takenAt: epoch, processes: processes), sessions: sessions, memory: memory)
  }

  // MARK: Inferred evidence stops where a person's own work begins

  @Test func `what an inferred daemon runs on a terminal is not claimed for the Project`() throws {
    // A terminal multiplexer started inside the Project, with shells that work elsewhere.
    let multiplexer = ProcessRecord.make(400, parent: 1, path: "/opt/bin/mux", cwd: "/work/alpha")
    let shell = ProcessRecord.make(
      401, parent: 400, path: "/bin/zsh", cwd: "/work/elsewhere", terminal: true)
    let server = ProcessRecord.make(
      402, parent: 401, path: "/opt/bin/vite", cwd: "/work/elsewhere", terminal: true)

    let result = inventory([root, multiplexer, shell, server], sessions: [session])

    let project = try #require(result.projects.first)
    #expect(project.loose.map(\.process.pid) == [400])
    #expect(result.unattributed.map(\.pid) == [401, 402])
  }

  @Test func `what an inferred daemon starts in another directory is not claimed either`() throws {
    let daemon = ProcessRecord.make(400, parent: 1, path: "/opt/bin/mux", cwd: "/work/alpha")
    let stray = ProcessRecord.make(401, parent: 400, path: "/opt/bin/tool", cwd: "/work/elsewhere")

    let result = inventory([root, daemon, stray], sessions: [session])

    #expect(result.projects.first?.loose.map(\.process.pid) == [400])
    #expect(result.unattributed.map(\.pid) == [401])
  }

  @Test func `what an inferred daemon starts inside the Project belongs to the Project`() throws {
    let daemon = ProcessRecord.make(400, parent: 1, path: "/opt/bin/biome", cwd: "/work/alpha")
    let worker = ProcessRecord.make(
      401, parent: 400, path: "/opt/bin/worker", cwd: "/work/alpha/web")
    let nowhere = ProcessRecord.make(402, parent: 400, path: "/opt/bin/worker", cwd: nil)

    let loose = try #require(
      inventory([root, daemon, worker, nowhere], sessions: [session]).projects.first?.loose)

    #expect(loose.map(\.process.pid) == [400, 401, 402])
    #expect(loose.allSatisfy { $0.evidence == .inferred })
  }

  @Test(arguments: ["/", "/Users/someone", "/Users"])
  func `nothing is inferred into the disk's root, the home directory or what is above it`(
    directory: String
  ) {
    let wide = Session.make("s1", root: root, project: directory)
    let daemon = ProcessRecord.make(
      400, parent: 1, path: "/opt/bin/agent", cwd: "/Users/someone/Library/Thing")
    let atRoot = ProcessRecord.make(401, parent: 1, path: "/opt/bin/agent", cwd: directory)

    let result = inventory([root, daemon, atRoot], sessions: [wide], home: "/Users/someone")

    #expect(result.unattributed.map(\.pid) == [400, 401])
  }

  // MARK: A Session that changed its identifier

  let renamed = SessionID(harness: .claudeCode, value: "s2")
  var before: Memory {
    var memory = Memory.empty
    memory.sessions[session.id] = Memory.PastSession(
      project: alpha, title: nil, markers: ["ID": "s1"], lastSeenAt: epoch, endedAt: nil)
    memory.lineage[root.key] = Memory.Lineage(session: session.id, project: alpha)
    return memory
  }

  @Test func `a process remembered under a Session's earlier identifier is still the Session's`()
    throws
  {
    // The same root process, now reporting another identifier, as after starting over.
    let later = Session.make("s2", root: root, project: "/work/alpha", markers: ["ID": "s2"])
    let escaped = ProcessRecord.make(300, parent: 1, path: "/opt/bin/node")
    let marked = ProcessRecord.make(301, parent: 1, path: "/opt/bin/node", markers: ["ID": "s1"])
    var memory = before
    memory.lineage[escaped.key] = Memory.Lineage(session: session.id, project: alpha)

    let result = inventory([root, escaped, marked], sessions: [later], memory: memory)

    let project = try #require(result.projects.first)
    #expect(project.loose.isEmpty)
    let processes = try #require(project.sessions.first?.processes)
    #expect(processes.map(\.process.pid) == [100, 300, 301])
    #expect(processes.map(\.evidence) == [.tree, .remembered, .tagged])
    #expect(processes.allSatisfy { !$0.isOrphan })
  }

  @Test func `a Session that changed its identifier keeps what was remembered for it`() {
    let later = Session.make("s2", root: root, project: "/work/alpha", markers: ["ID": "s2"])
    let escaped = ProcessRecord.make(300, parent: 1, path: "/opt/bin/node")
    var memory = before
    memory.lineage[escaped.key] = Memory.Lineage(session: session.id, project: alpha)
    let snapshot = Snapshot(takenAt: epoch.addingTimeInterval(10), processes: [root, escaped])

    memory.absorb(
      Reading(
        snapshot: snapshot, sessions: [later],
        inventory: Attributor().inventory(of: snapshot, sessions: [later], memory: memory)))

    #expect(memory.lineage[escaped.key]?.session == renamed)
    #expect(memory.sessions[session.id] == nil)
    #expect(memory.sessions[renamed]?.endedAt == nil)
  }

  @Test func `a Session that really ended is not mistaken for one that changed its identifier`()
    throws
  {
    // Another process has the identifier's old root now.
    let other = ProcessRecord.make(100, path: "/opt/bin/claude", startedAfter: 500, terminal: true)
    let later = Session.make("s2", root: other, project: "/work/alpha")
    let survivor = ProcessRecord.make(300, parent: 1, path: "/opt/bin/node")
    var memory = before
    memory.lineage[survivor.key] = Memory.Lineage(session: session.id, project: alpha)

    let project = try #require(
      inventory([other, survivor], sessions: [later], memory: memory).projects.first)

    #expect(project.loose.map(\.process.pid) == [300])
    #expect(project.loose.first?.isOrphan == true)
  }
}
