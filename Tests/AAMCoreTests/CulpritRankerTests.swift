import AAMCore
import Foundation
import Testing

struct UsageTests {
  @Test func `CPU use is the CPU time spent divided by the time that passed`() {
    let before = Snapshot(takenAt: epoch, processes: [.make(1, cpu: .seconds(10))])
    let after = Snapshot(
      takenAt: epoch.addingTimeInterval(10), processes: [.make(1, cpu: .seconds(15))])

    let usage = Usage(previous: before, current: after)

    #expect(usage.cpuPercent(of: ProcessRecord.make(1).key) == 50)
  }

  @Test func `a process that was not there before has no measured CPU use yet`() {
    let before = Snapshot(takenAt: epoch, processes: [])
    let after = Snapshot(
      takenAt: epoch.addingTimeInterval(10), processes: [.make(1, cpu: .seconds(15))])

    #expect(Usage(previous: before, current: after).cpuPercent(of: ProcessRecord.make(1).key) == 0)
  }

  @Test func `a recycled process identifier does not inherit the old process's CPU time`() {
    let before = Snapshot(takenAt: epoch, processes: [.make(1, cpu: .seconds(100))])
    let reborn = ProcessRecord.make(1, cpu: .seconds(1), startedAfter: 5)
    let after = Snapshot(takenAt: epoch.addingTimeInterval(10), processes: [reborn])

    #expect(Usage(previous: before, current: after).cpuPercent(of: reborn.key) == 0)
  }

  @Test func `snapshots taken at the same instant measure nothing`() {
    let before = Snapshot(takenAt: epoch, processes: [.make(1, cpu: .seconds(1))])
    let after = Snapshot(takenAt: epoch, processes: [.make(1, cpu: .seconds(2))])

    #expect(Usage(previous: before, current: after).cpuPercent(of: ProcessRecord.make(1).key) == 0)
  }
}

struct CulpritRankerTests {
  /// Builds two snapshots ten seconds apart in which each process spent `seconds` of CPU time.
  func measure(
    _ spent: [(ProcessRecord, seconds: Int64)],
    sessions: [Session] = []
  ) -> (Inventory, Usage) {
    let before = Snapshot(takenAt: epoch, processes: spent.map(\.0))
    let after = Snapshot(
      takenAt: epoch.addingTimeInterval(10),
      processes: spent.map { process, seconds in
        ProcessRecord(
          pid: process.pid,
          parentPID: process.parentPID,
          groupID: process.groupID,
          userID: process.userID,
          startedAt: process.startedAt,
          executablePath: process.executablePath,
          arguments: process.arguments,
          workingDirectory: process.workingDirectory,
          cpuTime: process.cpuTime + .seconds(seconds),
          residentBytes: process.residentBytes,
          isZombie: process.isZombie,
          hasTerminal: process.hasTerminal,
          markers: process.markers
        )
      }
    )
    return (
      Attributor().inventory(of: after, sessions: sessions),
      Usage(previous: before, current: after)
    )
  }

  @Test func `a Session is one Culprit with the load of its whole tree`() throws {
    let root = ProcessRecord.make(100, path: "/opt/bin/claude", rss: 1_000)
    let child = ProcessRecord.make(101, parent: 100, path: "/opt/bin/node", rss: 2_000)
    let session = Session.make("s1", root: root, project: "/work/alpha", title: "Fix login")
    let (inventory, usage) = measure([(root, 1), (child, 4)], sessions: [session])

    let culprits = CulpritRanker(threshold: 25).culprits(in: inventory, usage: usage)

    let culprit = try #require(culprits.first)
    #expect(culprits.count == 1)
    #expect(culprit.title == "Fix login")
    #expect(culprit.owner == .session(session.id, Project(root: "/work/alpha")))
    #expect(culprit.cpuPercent == 50)
    #expect(culprit.residentBytes == 3_000)
    #expect(culprit.processes.count == 2)
  }

  @Test func `a Session without a title is named after its Project`() throws {
    let root = ProcessRecord.make(100, path: "/opt/bin/claude")
    let session = Session.make("s1", root: root, project: "/work/alpha")
    let (inventory, usage) = measure([(root, 5)], sessions: [session])

    let culprit = try #require(CulpritRanker().culprits(in: inventory, usage: usage).first)

    #expect(culprit.title == "alpha")
  }

  @Test func `what stays under the threshold is not a Culprit`() {
    let quiet = ProcessRecord.make(7, path: "/usr/local/bin/quiet")
    let (inventory, usage) = measure([(quiet, 1)])

    #expect(CulpritRanker(threshold: 25).culprits(in: inventory, usage: usage).isEmpty)
  }

  @Test func `unattributed processes of one application are one Culprit`() throws {
    let renderer = ProcessRecord.make(
      30,
      path: "/Applications/Browser.app/Contents/Helpers/Browser Helper.app/Contents/MacOS/Helper")
    let gpu = ProcessRecord.make(31, path: "/Applications/Browser.app/Contents/MacOS/Browser")
    let (inventory, usage) = measure([(renderer, 2), (gpu, 2)])

    let culprits = CulpritRanker(threshold: 25).culprits(in: inventory, usage: usage)

    let culprit = try #require(culprits.first)
    #expect(culprits.count == 1)
    #expect(culprit.title == "Browser")
    #expect(culprit.owner == .none)
    #expect(culprit.cpuPercent == 40)
  }

  @Test func `unattributed processes outside an application are grouped by name`() throws {
    let first = ProcessRecord.make(40, path: "/usr/libexec/indexer")
    let second = ProcessRecord.make(41, path: "/usr/libexec/indexer")
    let (inventory, usage) = measure([(first, 2), (second, 2)])

    let culprit = try #require(CulpritRanker().culprits(in: inventory, usage: usage).first)

    #expect(culprit.title == "indexer")
    #expect(culprit.processes.count == 2)
  }

  @Test func `induced load is one Culprit under its own name`() throws {
    let first = ProcessRecord.make(50, path: "/usr/libexec/renderer")
    let second = ProcessRecord.make(51, path: "/usr/libexec/renderer")
    let unrelated = ProcessRecord.make(52, path: "/usr/libexec/renderer")
    let (inventory, usage) = measure([(first, 3), (second, 3), (unrelated, 4)])
    let load = InducedLoad(
      id: "web:example", title: "Web content of Example", processes: [first.key, second.key])

    let culprits = CulpritRanker().culprits(in: inventory, usage: usage, inducedLoad: [load])

    #expect(culprits.map(\.title) == ["Web content of Example", "renderer"])
    #expect(culprits.first?.cpuPercent == 60)
    #expect(culprits.first?.processes.count == 2)
  }

  @Test func `a process that belongs to a Project but to no Session is a Culprit of the Project`()
    throws
  {
    let root = ProcessRecord.make(100, path: "/opt/bin/claude", terminal: true)
    let daemon = ProcessRecord.make(400, path: "/opt/bin/watcher", cwd: "/work/alpha")
    let session = Session.make("s1", root: root, project: "/work/alpha")
    let (inventory, usage) = measure([(root, 0), (daemon, 5)], sessions: [session])

    let culprit = try #require(CulpritRanker().culprits(in: inventory, usage: usage).first)

    #expect(culprit.title == "watcher")
    #expect(culprit.owner == .project(Project(root: "/work/alpha")))
  }

  @Test func `Culprits are listed from the heaviest`() {
    let light = ProcessRecord.make(1, path: "/usr/local/bin/light")
    let heavy = ProcessRecord.make(2, path: "/usr/local/bin/heavy")
    let (inventory, usage) = measure([(light, 3), (heavy, 9)])

    let titles = CulpritRanker().culprits(in: inventory, usage: usage).map(\.title)

    #expect(titles == ["heavy", "light"])
  }
}
