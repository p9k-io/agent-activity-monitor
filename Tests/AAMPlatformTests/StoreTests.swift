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

  // MARK: Cleanup requests

  func request(_ id: String, after seconds: TimeInterval = 0) -> CleanupRequest {
    CleanupRequest(
      id: id, createdAt: epoch.addingTimeInterval(seconds),
      requester: SessionID(harness: .claudeCode, value: "s1"), reason: "left over from my tests",
      targets: [ProcessRecord.Key(pid: 4242, startedAt: epoch.addingTimeInterval(1.234567))])
  }

  @Test func `a Cleanup request that was filed is found again, the oldest first`() throws {
    let store = try Store(url: url)

    try store.add(request("b", after: 10))
    try store.add(request("a"))

    #expect(try store.requests() == [request("a"), request("b", after: 10)])
    #expect(try store.requests().first?.status == .pending)
  }

  @Test func `a decision on a Cleanup request is kept with what the Cleanup did`() throws {
    let store = try Store(url: url)
    try store.add(request("a"))
    var decided = request("a")
    decided.status = .done
    decided.decidedAt = epoch.addingTimeInterval(60)
    decided.outcome = CleanupRequest.Outcome(ended: 2, killed: 1, survived: 0, refused: 0)

    try store.update(decided)

    #expect(try store.requests() == [decided])
    #expect(try store.requests(status: .pending).isEmpty)
    #expect(try store.requests(status: .done) == [decided])
  }

  @Test func `a Cleanup request filed through one connection is seen through another`() throws {
    try Store(url: url).add(request("a"))

    #expect(try Store(url: url).requests(status: .pending).map(\.id) == ["a"])
  }

  @Test func `a Cleanup request filed outside any Session has no requester`() throws {
    let store = try Store(url: url)
    let anonymous = CleanupRequest(
      id: "x", createdAt: epoch, requester: nil, reason: "", targets: [])

    try store.add(anonymous)

    #expect(try store.requests() == [anonymous])
  }
}
