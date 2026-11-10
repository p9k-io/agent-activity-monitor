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

  // MARK: History

  let alpha = Project(root: "/work/alpha")
  let first = SessionID(harness: .claudeCode, value: "s1")

  func bucket(
    at seconds: TimeInterval, cpu: Double, peak: UInt64 = 0, kind: ProcessKind = .testRunner,
    session: SessionID? = SessionID(harness: .claudeCode, value: "s1")
  ) -> HistoryBucket {
    HistoryBucket(
      minute: epoch.addingTimeInterval(seconds), project: alpha, session: session, kind: kind,
      cpuSeconds: cpu, peakResidentBytes: peak)
  }

  @Test func `CPU time recorded for the same minute is added up and the larger peak is kept`()
    throws
  {
    let store = try Store(url: url)

    try store.record([bucket(at: 0, cpu: 10, peak: 500)])
    try store.record([bucket(at: 0, cpu: 5, peak: 300)])

    #expect(
      try store.usageTotals(since: epoch)
        == [UsageTotal(project: alpha, session: first, kind: .testRunner, cpuSeconds: 15)])
    #expect(
      try store.usagePeaks(since: epoch)
        == [UsagePeak(project: alpha, session: first, residentBytes: 500)])
  }

  @Test func `a period leaves out what happened before it`() throws {
    let store = try Store(url: url)

    try store.record([bucket(at: -120, cpu: 100), bucket(at: 0, cpu: 10)])

    #expect(try store.usageTotals(since: epoch.addingTimeInterval(-60)).map(\.cpuSeconds) == [10])
  }

  @Test func `the peak of a Session is the most its kinds of process held in one minute`() throws {
    let store = try Store(url: url)

    try store.record([
      bucket(at: 0, cpu: 1, peak: 500), bucket(at: 0, cpu: 1, peak: 300, kind: .harness),
      bucket(at: 60, cpu: 1, peak: 600),
    ])

    #expect(try store.usagePeaks(since: epoch).map(\.residentBytes) == [800])
  }

  @Test func `what belongs to no Session is kept apart from the Sessions`() throws {
    let store = try Store(url: url)

    try store.record([bucket(at: 0, cpu: 4), bucket(at: 0, cpu: 6, session: nil)])

    let totals = try store.usageTotals(since: epoch)
    #expect(Set(totals.map(\.session)) == [first, nil])
    #expect(totals.first { $0.session == nil }?.cpuSeconds == 6)
  }

  @Test func `history and decided requests older than the retention are dropped`() throws {
    let store = try Store(url: url)
    try store.record([bucket(at: -100, cpu: 1), bucket(at: 0, cpu: 2)])
    var decided = request("old-decided", after: -100)
    decided.status = .denied
    decided.decidedAt = epoch.addingTimeInterval(-90)
    var recent = request("recent-decided", after: -100)
    recent.status = .denied
    recent.decidedAt = epoch
    for filed in [decided, recent, request("old-waiting", after: -100)] {
      try store.add(filed)
      try store.update(filed)
    }

    try store.prune(before: epoch.addingTimeInterval(-50))

    #expect(try store.usageTotals(since: .distantPast).map(\.cpuSeconds) == [2])
    #expect(try store.requests().map(\.id) == ["old-waiting", "recent-decided"])
  }
}
