import AAMCore
import Foundation
import Testing

struct HistoryRecorderTests {
  let alpha = Project(root: "/work/alpha")
  let root = ProcessRecord.make(100, path: "/opt/bin/claude", rss: 300, terminal: true)
  let tests = ProcessRecord.make(
    101, parent: 100, path: "/opt/bin/node", arguments: ["node", "node_modules/.bin/vitest"],
    rss: 500)
  let daemon = ProcessRecord.make(400, path: "/opt/bin/biome", cwd: "/work/alpha", rss: 50)
  let stranger = ProcessRecord.make(900, path: "/usr/libexec/other", rss: 999)
  var session: Session { Session.make("s1", root: root) }

  func inventory(_ processes: [ProcessRecord]) -> Inventory {
    Attributor().inventory(
      of: Snapshot(takenAt: epoch, processes: processes), sessions: [session], memory: .empty)
  }

  func usage(_ percent: [(ProcessRecord, Double)]) -> Usage {
    Usage(Dictionary(uniqueKeysWithValues: percent.map { ($0.0.key, $0.1) }))
  }

  @Test func `CPU time is added up per minute, Session and kind of process`() {
    var recorder = HistoryRecorder()
    let inventory = inventory([root, tests])

    // 150 % for ten seconds is fifteen seconds of CPU time. Twice.
    recorder.record(inventory, usage: usage([(tests, 150)]), elapsed: 10, at: epoch)
    recorder.record(
      inventory, usage: usage([(tests, 150)]), elapsed: 10, at: epoch.addingTimeInterval(10))

    #expect(
      recorder.drain() == [
        // The fixtures' epoch is the start of a minute.
        HistoryBucket(
          minute: epoch, project: alpha, session: session.id, kind: .testRunner, cpuSeconds: 30,
          peakResidentBytes: 500)
      ])
  }

  @Test func `what is nearly idle at a look is not counted`() {
    var recorder = HistoryRecorder()

    recorder.record(
      inventory([root, tests]), usage: usage([(tests, 0.9), (root, 0)]), elapsed: 10, at: epoch)

    #expect(recorder.drain().isEmpty)
  }

  @Test func `a minute is told by where it starts`() {
    var recorder = HistoryRecorder()

    recorder.record(
      inventory([root, tests]), usage: usage([(tests, 100)]), elapsed: 10,
      at: epoch.addingTimeInterval(119.5))

    #expect(recorder.drain().map(\.minute) == [epoch.addingTimeInterval(60)])
  }

  @Test func `a new minute starts a new bucket`() {
    var recorder = HistoryRecorder()
    let inventory = inventory([root, tests])

    recorder.record(inventory, usage: usage([(tests, 100)]), elapsed: 10, at: epoch)
    recorder.record(
      inventory, usage: usage([(tests, 100)]), elapsed: 10, at: epoch.addingTimeInterval(60))

    #expect(recorder.drain().map(\.cpuSeconds) == [10, 10])
  }

  @Test func `memory is the most the processes of a kind held together at one look`() {
    var recorder = HistoryRecorder()
    let second = ProcessRecord.make(
      102, parent: 100, path: "/opt/bin/node", arguments: ["node", "node_modules/.bin/vitest"],
      rss: 700)

    recorder.record(
      inventory([root, tests, second]), usage: usage([(tests, 100), (second, 100)]), elapsed: 10,
      at: epoch)
    recorder.record(
      inventory([root, tests]), usage: usage([(tests, 100)]), elapsed: 10,
      at: epoch.addingTimeInterval(10))

    #expect(recorder.drain().map(\.peakResidentBytes) == [1200])
  }

  @Test func `a process of the Project that belongs to no Session is counted for the Project`() {
    var recorder = HistoryRecorder()

    recorder.record(
      inventory([root, daemon, stranger]), usage: usage([(daemon, 60), (stranger, 400)]),
      elapsed: 10, at: epoch)

    let buckets = recorder.drain()
    #expect(buckets.map(\.project) == [alpha])
    #expect(buckets.map(\.session) == [nil])
    #expect(buckets.map(\.cpuSeconds) == [6])
  }

  @Test func `draining leaves nothing behind`() {
    var recorder = HistoryRecorder()
    recorder.record(inventory([root, tests]), usage: usage([(tests, 100)]), elapsed: 10, at: epoch)

    _ = recorder.drain()

    #expect(recorder.drain().isEmpty)
  }
}

struct UsageReportTests {
  let alpha = Project(root: "/work/alpha")
  let beta = Project(root: "/work/beta")
  let first = SessionID(harness: .claudeCode, value: "s1")
  let second = SessionID(harness: .codex, value: "s2")

  @Test func `CPU time is totalled per Session, the heaviest first, with what it went on`() {
    let report = UsageReport(
      totals: [
        UsageTotal(project: alpha, session: first, kind: .testRunner, cpuSeconds: 600),
        UsageTotal(project: alpha, session: first, kind: .harness, cpuSeconds: 100),
        UsageTotal(project: beta, session: second, kind: .devServer, cpuSeconds: 900),
        UsageTotal(project: alpha, session: nil, kind: .languageServer, cpuSeconds: 50),
      ],
      peaks: [
        UsagePeak(project: alpha, session: first, residentBytes: 2000),
        UsagePeak(project: beta, session: second, residentBytes: 1000),
      ],
      titles: [first: "Fix login"])

    #expect(report.rows.map(\.cpuSeconds) == [900, 700, 50])
    #expect(report.rows.map(\.session) == [second, first, nil])
    #expect(report.rows.map(\.title) == ["beta", "Fix login", "Not tied to one Session"])
    #expect(report.rows.map(\.peakResidentBytes) == [1000, 2000, 0])
    #expect(report.rows[1].byKind.map(\.kind) == [.testRunner, .harness])
    #expect(report.rows[1].byKind.map(\.cpuSeconds) == [600, 100])
    #expect(report.cpuSeconds == 1650)
  }

  @Test func `Projects are totalled from their Sessions, the heaviest first`() {
    let report = UsageReport(
      totals: [
        UsageTotal(project: alpha, session: first, kind: .testRunner, cpuSeconds: 600),
        UsageTotal(project: alpha, session: nil, kind: .languageServer, cpuSeconds: 500),
        UsageTotal(project: beta, session: second, kind: .devServer, cpuSeconds: 900),
      ], peaks: [], titles: [:])

    #expect(report.projects.map(\.project) == [alpha, beta])
    #expect(report.projects.map(\.cpuSeconds) == [1100, 900])
  }

  @Test func `nothing recorded gives an empty report`() {
    let report = UsageReport(totals: [], peaks: [], titles: [:])

    #expect(report.rows.isEmpty)
    #expect(report.cpuSeconds == 0)
  }

  @Test(arguments: [
    (59.0, "59s"), (60, "1m"), (3599, "59m"), (3600, "1h 0m"), (90_000, "25h 0m"), (0.4, "0s"),
  ])
  func `CPU time is told in hours and minutes, without days`(seconds: Double, text: String) {
    #expect(Format.cpuTime(seconds) == text)
  }
}
