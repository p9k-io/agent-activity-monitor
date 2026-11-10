import AAMCore
import Testing

private struct FixedSource: ProcessSource {
  let processes: [ProcessRecord]

  func snapshot() -> Snapshot {
    Snapshot(takenAt: epoch, processes: processes)
  }
}

private struct FixedAdapter: HarnessAdapter {
  let harness: HarnessID
  let markerNames: Set<String> = []
  let rootPID: Int32

  func sessions(in snapshot: Snapshot) -> [Session] {
    snapshot.processes
      .filter { $0.pid == rootPID }
      .map { Session.make("s-\(rootPID)", root: $0, harness: harness) }
  }
}

struct ObserverTests {
  let processes: [ProcessRecord] = [
    .make(100, path: "/opt/bin/claude"),
    .make(101, parent: 100, path: "/opt/bin/node"),
    .make(200, path: "/opt/bin/codex"),
    .make(300, path: "/usr/local/bin/other"),
  ]

  var observer: Observer {
    Observer(
      source: FixedSource(processes: processes),
      adapters: [
        FixedAdapter(harness: .claudeCode, rootPID: 100),
        FixedAdapter(harness: .codex, rootPID: 200),
      ])
  }

  @Test func `an observation holds the Sessions of every Harness and where each process belongs`() {
    let observation = observer.observe()

    #expect(observation.sessions.map(\.id.harness) == [.claudeCode, .codex])
    #expect(observation.inventory.projects.flatMap(\.sessions).count == 2)
    #expect(observation.inventory.unattributed.map(\.pid) == [300])
  }

  @Test func `the Session a process belongs to is found from any process in its tree`() {
    let inventory = observer.observe().inventory

    #expect(inventory.session(owning: 101)?.session.id.value == "s-100")
    #expect(inventory.session(owning: 100)?.session.id.value == "s-100")
    #expect(inventory.session(owning: 300) == nil)
  }

  @Test func `a Session's memory is the sum over its processes`() throws {
    let source = FixedSource(processes: [
      .make(100, path: "/opt/bin/claude", rss: 1_000),
      .make(101, parent: 100, path: "/opt/bin/node", rss: 2_500),
    ])
    let observer = Observer(
      source: source, adapters: [FixedAdapter(harness: .claudeCode, rootPID: 100)])

    let group = try #require(observer.observe().inventory.session(owning: 100))

    #expect(group.residentBytes == 3_500)
  }
}
