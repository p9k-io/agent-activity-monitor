import AAMCore
import AAMPlatform
import Foundation
import Testing

struct SamplerTests {
  let scratch: TemporaryDirectory

  init() throws {
    scratch = try TemporaryDirectory()
  }

  /// A process with the given CPU time. The current user is 501 in these fixtures.
  func process(
    _ pid: Int32, path: String = "/opt/bin/worker", cpu seconds: Int64, user: UInt32 = 501
  ) -> ProcessRecord {
    ProcessRecord(
      pid: pid, parentPID: 1, groupID: pid, userID: user, startedAt: epoch, executablePath: path,
      arguments: [], workingDirectory: "/work/alpha", cpuTime: .seconds(seconds),
      residentBytes: 100, isZombie: false, hasTerminal: false, markers: [:])
  }

  func snapshot(after seconds: TimeInterval, _ processes: ProcessRecord...) -> Snapshot {
    Snapshot(takenAt: epoch.addingTimeInterval(seconds), processes: processes)
  }

  func sampler(
    _ snapshots: [Snapshot], adapter: ClaudeLike = ClaudeLike(), store: Store? = nil,
    refreshOthersEvery: Int = 6, saveEvery: Int = 6
  ) -> (Sampler, ScriptedSource) {
    let source = ScriptedSource(snapshots)
    let sampler = Sampler(
      source: source, observer: Observer(source: source, adapters: [adapter]), store: store,
      ownUser: 501, refreshOthersEvery: refreshOthersEvery, saveEvery: saveEvery)
    return (sampler, source)
  }

  @Test func `the first sample measures nothing and the second measures the time between them`()
    async
  {
    let (sampler, _) = sampler([
      snapshot(after: 0, process(1, cpu: 0)),
      snapshot(after: 10, process(1, cpu: 5)),
    ])

    let first = await sampler.tick()
    let second = await sampler.tick()

    #expect(first.culprits.isEmpty)
    #expect(second.culprits.map(\.culprit.title) == ["worker"])
    #expect(second.culprits.first?.culprit.cpuPercent == 50)
  }

  @Test func `other users' processes are measured between the looks that refresh them`() async {
    let own = process(1, cpu: 0)
    let (sampler, source) = sampler(
      [
        snapshot(after: 0, own, process(2, path: "/usr/libexec/indexer", cpu: 0, user: 0)),
        snapshot(after: 5, own, process(2, path: "/usr/libexec/indexer", cpu: 0, user: 0)),
        snapshot(after: 10, own, process(2, path: "/usr/libexec/indexer", cpu: 0, user: 0)),
        snapshot(after: 15, own, process(2, path: "/usr/libexec/indexer", cpu: 15, user: 0)),
        snapshot(after: 20, own, process(2, path: "/usr/libexec/indexer", cpu: 15, user: 0)),
      ], refreshOthersEvery: 3)

    var samples: [Sample] = []
    for _ in 0..<5 {
      samples.append(await sampler.tick())
    }

    // Fifteen seconds of CPU over the fifteen seconds between the two refreshes, not over
    // the five seconds since the look before.
    #expect(samples[3].culprits.first?.culprit.cpuPercent == 100)
    #expect(samples[4].culprits.first?.culprit.cpuPercent == 100)
    #expect(source.refreshes == [true, false, false, true, false])
  }

  @Test func `a Culprit keeps the time it became one`() async {
    let (sampler, _) = sampler([
      snapshot(after: 0, process(1, cpu: 0)),
      snapshot(after: 10, process(1, cpu: 10)),
      snapshot(after: 20, process(1, cpu: 20)),
    ])

    _ = await sampler.tick()
    _ = await sampler.tick()
    let third = await sampler.tick()

    #expect(third.culprits.first?.hotSince == epoch.addingTimeInterval(10))
  }

  @Test func `what is remembered reaches the store`() async throws {
    let url = scratch.url.appendingPathComponent("aam.sqlite")
    let claude = process(100, path: "/opt/bin/claude", cpu: 0)
    let (sampler, _) = sampler([snapshot(after: 0, claude)], store: try Store(url: url))

    _ = await sampler.tick()

    #expect(try Store(url: url).loadMemory().sessions.count == 1)
  }

  @Test func `the CPU time a Session used reaches the store`() async throws {
    let url = scratch.url.appendingPathComponent("aam.sqlite")
    let (sampler, _) = sampler(
      [
        snapshot(after: 0, process(100, path: "/opt/bin/claude", cpu: 0)),
        snapshot(after: 10, process(100, path: "/opt/bin/claude", cpu: 4)),
      ], store: try Store(url: url), saveEvery: 1)

    _ = await sampler.tick()
    _ = await sampler.tick()

    let totals = try Store(url: url).usageTotals(since: epoch)
    #expect(totals.map(\.kind) == [.harness])
    #expect(totals.map(\.cpuSeconds) == [4])
    #expect(totals.map(\.session) == [SessionID(harness: .claudeCode, value: "s-100")])
  }

  @Test func `history adds up to what the looks measured over fifteen minutes`() async throws {
    let url = scratch.url.appendingPathComponent("aam.sqlite")
    // Ninety looks ten seconds apart. The Session's root uses a different amount each time.
    var spent: Int64 = 0
    var snapshots: [Snapshot] = []
    for look in 0...90 {
      spent += Int64(1 + look % 7)
      snapshots.append(
        snapshot(after: Double(look) * 10, process(100, path: "/opt/bin/claude", cpu: spent)))
    }
    let measured = Double(spent - 1)
    let (sampler, _) = sampler(snapshots, store: try Store(url: url))

    for _ in snapshots {
      _ = await sampler.tick()
    }
    await sampler.flush()

    let report = try Store(url: url).usageReport(since: epoch)
    #expect(abs(report.cpuSeconds - measured) < 0.001)
    #expect(report.rows.count == 1)
  }

  @Test func `without a store, history does not pile up in memory`() async {
    let (sampler, _) = sampler(
      [
        snapshot(after: 0, process(100, path: "/opt/bin/claude", cpu: 0)),
        snapshot(after: 10, process(100, path: "/opt/bin/claude", cpu: 4)),
        snapshot(after: 80, process(100, path: "/opt/bin/claude", cpu: 30)),
      ], saveEvery: 1)

    for _ in 0..<3 {
      _ = await sampler.tick()
    }

    #expect(await sampler.historyBacklog == 0)
  }

  @Test func `changing the thresholds changes what is Stale`() async {
    let claude = process(100, path: "/opt/bin/claude", cpu: 0)
    let adapter = ClaudeLike(state: .idle, lastActivityAt: epoch.addingTimeInterval(-7200))
    let (sampler, _) = sampler([snapshot(after: 0, claude)], adapter: adapter)

    let lenient = await sampler.tick()
    await sampler.update(
      Sampler.Settings(thresholds: StaleThresholds(idleSession: .seconds(3600))))
    let strict = await sampler.tick()

    #expect(lenient.findings.isEmpty)
    #expect(strict.findings.map(\.kind) == [.idleSession])
  }
}
