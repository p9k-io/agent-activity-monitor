import AAMCore
import AAMPlatform
import Foundation
import Testing

private struct ListedSource: ProcessSource {
  let processes: [ProcessRecord]
  var after: TimeInterval = 0

  func snapshot() -> Snapshot {
    Snapshot(takenAt: epoch.addingTimeInterval(after), processes: processes)
  }
}

struct MonitorTests {
  let scratch: TemporaryDirectory
  let url: URL
  let root = ProcessRecord.make(100, path: "/opt/bin/claude")
  let child = ProcessRecord.make(101, parent: 100, path: "/opt/bin/node")

  init() throws {
    scratch = try TemporaryDirectory()
    url = scratch.url.appendingPathComponent("aam.sqlite")
  }

  func monitor(_ processes: [ProcessRecord], after: TimeInterval = 0, store: Store?) -> Monitor {
    Monitor(
      observer: Observer(
        source: ListedSource(processes: processes, after: after), adapters: [ClaudeLike()]),
      store: store)
  }

  @Test func `a process that outlives its Session is an Orphan on a later look`() throws {
    _ = monitor([root, child], store: try Store(url: url)).look()
    let reparented = ProcessRecord.make(101, parent: 1, path: "/opt/bin/node")

    // A new connection, as when the command line tool runs again.
    let later = monitor([reparented], after: 300, store: try Store(url: url)).look()

    let orphan = try #require(later.observation.inventory.projects.first?.loose.first)
    #expect(orphan.isOrphan)
    #expect(orphan.formerSession == SessionID(harness: .claudeCode, value: "s-100"))
    #expect(orphan.evidence == .remembered)
  }

  @Test func `the end of a Session is remembered from the look that missed it`() throws {
    _ = monitor([root, child], store: try Store(url: url)).look()

    let later = monitor([child], after: 300, store: try Store(url: url)).look()

    let session = SessionID(harness: .claudeCode, value: "s-100")
    #expect(later.memory.sessions[session]?.endedAt == epoch.addingTimeInterval(300))
  }

  @Test func `activity is recorded only by a look that follows another`() throws {
    let store = try Store(url: url)
    let first = monitor([root, child], store: store).look()
    #expect(first.memory.activityAsOf == nil)
    #expect(first.usage == nil)

    let second = monitor([root, child], after: 5, store: store).look(after: first.observation)

    #expect(second.memory.activityAsOf == epoch.addingTimeInterval(5))
    #expect(second.usage != nil)
  }

  @Test func `without a store a look still sorts what it sees`() {
    let look = monitor([root, child], store: nil).look()

    #expect(look.observation.inventory.projects.first?.sessions.first?.processes.count == 2)
    #expect(look.memory.sessions.count == 1)
  }
}
