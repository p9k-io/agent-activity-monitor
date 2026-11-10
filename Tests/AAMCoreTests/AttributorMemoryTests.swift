import AAMCore
import Foundation
import Testing

struct AttributorMemoryTests {
  let root = ProcessRecord.make(100, path: "/opt/bin/claude", terminal: true)
  let alpha = Project(root: "/work/alpha")
  var session: Session {
    Session.make("s1", root: root, project: "/work/alpha", markers: ["ID": "s1"])
  }
  var ended: Memory {
    var memory = Memory.empty
    memory.sessions[session.id] = Memory.PastSession(
      project: alpha, title: nil, markers: ["ID": "s1"], lastSeenAt: epoch,
      endedAt: epoch.addingTimeInterval(10))
    return memory
  }

  func inventory(
    _ processes: [ProcessRecord], sessions: [Session] = [], memory: Memory = .empty
  ) -> Inventory {
    Attributor().inventory(
      of: Snapshot(takenAt: epoch.addingTimeInterval(60), processes: processes),
      sessions: sessions, memory: memory)
  }

  @Test func `a process that left the tree of a live Session is still its own, as Remembered`()
    throws
  {
    let escaped = ProcessRecord.make(300, parent: 1, path: "/opt/bin/node")
    var memory = Memory.empty
    memory.lineage[escaped.key] = Memory.Lineage(session: session.id, project: alpha)

    let result = inventory([root, escaped], sessions: [session], memory: memory)

    let found = try #require(
      result.projects.first?.sessions.first?.processes.first { $0.process.pid == 300 })
    #expect(found.evidence == .remembered)
    #expect(!found.isOrphan)
  }

  @Test func `a process remembered from a Session that ended is an Orphan in its Project`() throws {
    let survivor = ProcessRecord.make(300, parent: 1, path: "/opt/bin/node")
    var memory = ended
    memory.lineage[survivor.key] = Memory.Lineage(session: session.id, project: alpha)

    let result = inventory([survivor], memory: memory)

    let project = try #require(result.projects.first)
    #expect(project.project == alpha)
    #expect(project.sessions.isEmpty)
    let orphan = try #require(project.loose.first)
    #expect(orphan.isOrphan)
    #expect(orphan.formerSession == session.id)
    #expect(orphan.evidence == .remembered)
  }

  @Test func `a process marked by a Session that ended is an Orphan of that Session`() throws {
    let survivor = ProcessRecord.make(300, parent: 1, path: "/opt/bin/node", markers: ["ID": "s1"])

    let orphan = try #require(inventory([survivor], memory: ended).projects.first?.loose.first)

    #expect(orphan.isOrphan)
    #expect(orphan.formerSession == session.id)
    #expect(orphan.evidence == .tagged)
  }

  @Test func `a process marked by a Session nobody saw is an Orphan in the Project it runs in`()
    throws
  {
    let stranger = ProcessRecord.make(
      300, parent: 1, path: "/opt/bin/node", cwd: "/work/beta", markers: ["ID": "never-seen"])

    let project = try #require(inventory([stranger]).projects.first)

    #expect(project.project == Project(root: "/work/beta"))
    #expect(project.loose.first?.isOrphan == true)
    #expect(project.loose.first?.formerSession == nil)
    #expect(project.loose.first?.evidence == .tagged)
  }

  @Test func `a daemon running inside a known Project belongs to it by inference`() throws {
    let daemon = ProcessRecord.make(400, parent: 1, path: "/opt/bin/biome", cwd: "/work/alpha/web")

    let project = try #require(inventory([root, daemon], sessions: [session]).projects.first)

    let found = try #require(project.loose.first)
    #expect(found.evidence == .inferred)
    #expect(!found.isOrphan)
  }

  @Test func `a Project that only had Sessions before is still known`() throws {
    let daemon = ProcessRecord.make(400, parent: 1, path: "/opt/bin/biome", cwd: "/work/alpha")

    let project = try #require(inventory([daemon], memory: ended).projects.first)

    #expect(project.project == alpha)
    #expect(project.loose.first?.evidence == .inferred)
  }

  @Test(arguments: [
    ProcessRecord.make(400, parent: 1, path: "/opt/bin/tool", cwd: "/work/alpha", terminal: true),
    ProcessRecord.make(401, parent: 77, path: "/opt/bin/tool", cwd: "/work/alpha"),
    ProcessRecord.make(402, parent: 1, path: "/opt/bin/tool", cwd: "/work/alpha-two"),
    ProcessRecord.make(403, parent: 1, path: "/opt/bin/tool", cwd: nil),
  ])
  func `nothing is inferred for a person's own terminal work or for another directory`(
    process: ProcessRecord
  ) {
    let result = inventory([root, process], sessions: [session])

    #expect(result.projects.first?.loose.isEmpty == true)
    #expect(result.unattributed.map(\.pid) == [process.pid])
  }

  @Test func `what an Orphan started is an Orphan too`() throws {
    let survivor = ProcessRecord.make(300, parent: 1, path: "/opt/bin/node", markers: ["ID": "s1"])
    let child = ProcessRecord.make(301, parent: 300, path: "/opt/bin/esbuild")

    let loose = try #require(inventory([survivor, child], memory: ended).projects.first?.loose)

    #expect(loose.map(\.process.pid) == [300, 301])
    #expect(loose.allSatisfy { $0.isOrphan && $0.formerSession == session.id })
  }

  @Test func `the root of a Session is its Harness and the rest is classified`() throws {
    let server = ProcessRecord.make(
      101, parent: 100, path: "/opt/bin/node", arguments: ["npm", "exec", "some-mcp"])

    let processes = try #require(
      inventory([root, server], sessions: [session]).projects.first?.sessions.first?.processes)

    #expect(processes.map(\.kind) == [.harness, .mcpServer])
  }
}
