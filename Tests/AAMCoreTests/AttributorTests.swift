import AAMCore
import Testing

struct AttributorTests {
  let root = ProcessRecord.make(100, parent: 50, path: "/opt/bin/claude", terminal: true)
  let server = ProcessRecord.make(101, parent: 100, path: "/opt/bin/node")
  let worker = ProcessRecord.make(102, parent: 101, path: "/opt/bin/node")
  let shell = ProcessRecord.make(50, parent: 1, path: "/bin/zsh")

  func inventory(
    _ processes: [ProcessRecord],
    sessions: [Session]
  ) -> Inventory {
    Attributor().inventory(of: Snapshot(takenAt: epoch, processes: processes), sessions: sessions)
  }

  @Test func `a Session tree holds the root and every descendant with Tree evidence`() throws {
    let session = Session.make("s1", root: root)

    let result = inventory([shell, root, server, worker], sessions: [session])

    let group = try #require(result.projects.first?.sessions.first)
    #expect(group.session.id == session.id)
    #expect(group.processes.map(\.process.pid) == [100, 101, 102])
    #expect(group.processes.allSatisfy { $0.evidence == .tree })
    #expect(result.unattributed.map(\.pid) == [50])
  }

  @Test func `a Session started inside another owns its own subtree`() throws {
    let inner = ProcessRecord.make(110, parent: 101, path: "/opt/bin/codex")
    let innerChild = ProcessRecord.make(111, parent: 110, path: "/opt/bin/node")
    let outerSession = Session.make("outer", root: root)
    let innerSession = Session.make("inner", root: inner, harness: .codex)

    let result = inventory(
      [root, server, inner, innerChild],
      sessions: [outerSession, innerSession]
    )

    let sessions = try #require(result.projects.first?.sessions)
    let outer = try #require(sessions.first { $0.session.id == outerSession.id })
    let nested = try #require(sessions.first { $0.session.id == innerSession.id })
    #expect(outer.processes.map(\.process.pid) == [100, 101])
    #expect(nested.processes.map(\.process.pid) == [110, 111])
  }

  @Test func `a process outside the tree that carries the Session marker is Tagged`() throws {
    let session = Session.make("s1", root: root, markers: ["SESSION_ID": "s1"])
    let escaped = ProcessRecord.make(
      300, parent: 1, path: "/opt/bin/node", markers: ["SESSION_ID": "s1"])

    let result = inventory([root, escaped], sessions: [session])

    let group = try #require(result.projects.first?.sessions.first)
    let tagged = try #require(group.processes.first { $0.process.pid == 300 })
    #expect(tagged.evidence == .tagged)
    #expect(result.unattributed.isEmpty)
  }

  @Test func `a marker that matches no live Session attributes nothing`() {
    let session = Session.make("s1", root: root, markers: ["SESSION_ID": "s1"])
    let stranger = ProcessRecord.make(
      300, parent: 1, path: "/opt/bin/node", markers: ["SESSION_ID": "gone"])

    let result = inventory([root, stranger], sessions: [session])

    #expect(result.unattributed.map(\.pid) == [300])
  }

  @Test func `Sessions in the same Project share one Project entry`() throws {
    let other = ProcessRecord.make(200, parent: 50, path: "/opt/bin/codex")
    let first = Session.make("a", root: root, project: "/work/alpha")
    let second = Session.make("b", root: other, harness: .codex, project: "/work/alpha")

    let result = inventory([root, other], sessions: [first, second])

    #expect(result.projects.count == 1)
    #expect(result.projects.first?.sessions.count == 2)
  }

  @Test func `Projects are listed by name`() {
    let other = ProcessRecord.make(200, parent: 50, path: "/opt/bin/codex")
    let zulu = Session.make("z", root: root, project: "/work/zulu")
    let alpha = Session.make("a", root: other, project: "/work/alpha")

    let result = inventory([root, other], sessions: [zulu, alpha])

    #expect(result.projects.map(\.project.name) == ["alpha", "zulu"])
  }

  @Test func `a Session whose root process is gone is left out`() {
    let ghost = Session.make("ghost", root: .make(999, path: "/opt/bin/claude"))

    let result = inventory([shell], sessions: [ghost])

    #expect(result.projects.isEmpty)
    #expect(result.unattributed.map(\.pid) == [50])
  }

  @Test func `a recycled process identifier is not mistaken for the Session root`() {
    let recycled = ProcessRecord.make(100, parent: 1, path: "/bin/sleep", startedAfter: 500)
    let session = Session.make("s1", root: root)

    let result = inventory([recycled], sessions: [session])

    #expect(result.projects.isEmpty)
    #expect(result.unattributed.map(\.pid) == [100])
  }
}
