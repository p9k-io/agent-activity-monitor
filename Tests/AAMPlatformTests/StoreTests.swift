import AAMCore
import AAMPlatform
import Foundation
import Testing

struct StoreTests {
  let scratch: TemporaryDirectory
  let url: URL

  init() throws {
    scratch = try TemporaryDirectory()
    url = scratch.url.appendingPathComponent("state/aam.sqlite")
  }

  /// Memory with one running Session, one ended Session and a remembered process.
  func sample() -> Memory {
    let running = SessionID(harness: .claudeCode, value: "running")
    let ended = SessionID(harness: .codex, value: "ended")
    let process = ProcessRecord.Key(pid: 4242, startedAt: epoch.addingTimeInterval(1.234567))
    var memory = Memory.empty
    memory.sessions[running] = Memory.PastSession(
      project: Project(root: "/work/alpha"), title: "Fix login", markers: ["ID": "running"],
      lastSeenAt: epoch.addingTimeInterval(60), endedAt: nil)
    memory.sessions[ended] = Memory.PastSession(
      project: Project(root: "/work/beta"), title: nil, markers: [:],
      lastSeenAt: epoch, endedAt: epoch.addingTimeInterval(30))
    memory.lineage[process] = Memory.Lineage(
      session: running, project: Project(root: "/work/alpha"))
    memory.lastBusyAt[process] = epoch.addingTimeInterval(45.5)
    memory.activityAsOf = epoch.addingTimeInterval(60)
    return memory
  }

  @Test func `a new store remembers nothing`() throws {
    #expect(try Store(url: url).loadMemory() == .empty)
  }

  @Test func `what is saved is loaded back unchanged`() throws {
    let store = try Store(url: url)

    try store.save(sample())

    #expect(try store.loadMemory() == sample())
  }

  @Test func `saving replaces what was remembered before`() throws {
    let store = try Store(url: url)
    try store.save(sample())
    var smaller = sample()
    smaller.lineage = [:]
    smaller.lastBusyAt = [:]
    smaller.sessions.removeValue(forKey: SessionID(harness: .codex, value: "ended"))

    try store.save(smaller)

    #expect(try store.loadMemory() == smaller)
  }

  @Test func `a second connection to the same file sees what the first one saved`() throws {
    try Store(url: url).save(sample())

    #expect(try Store(url: url).loadMemory() == sample())
  }

  @Test func `the store file can be read by its owner only`() throws {
    _ = try Store(url: url)

    let permissions = try #require(
      FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)
    #expect(permissions.intValue & 0o077 == 0)
  }

  @Test func `a file that is not a database is refused`() throws {
    try scratch.file("state/aam.sqlite", "this is not a database, just some text\n")

    #expect(throws: StoreError.self) {
      try Store(url: url)
    }
  }
}
