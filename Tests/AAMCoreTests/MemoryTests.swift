import AAMCore
import Foundation
import Testing

struct MemoryTests {
  let root = ProcessRecord.make(100, path: "/opt/bin/claude")
  let child = ProcessRecord.make(101, parent: 100, path: "/opt/bin/node")
  var session: Session {
    Session.make(
      "s1", root: root, project: "/work/alpha", title: "Fix login", markers: ["ID": "s1"])
  }

  func observation(
    _ processes: [ProcessRecord], sessions: [Session], after seconds: TimeInterval = 0,
    memory: Memory = .empty
  ) -> Observation {
    let snapshot = Snapshot(takenAt: epoch.addingTimeInterval(seconds), processes: processes)
    return Observation(
      snapshot: snapshot,
      sessions: sessions,
      inventory: Attributor().inventory(of: snapshot, sessions: sessions, memory: memory))
  }

  @Test func `a live Session and the processes of its tree are remembered`() {
    var memory = Memory.empty

    memory.absorb(observation([root, child], sessions: [session]))

    #expect(memory.sessions[session.id]?.project == Project(root: "/work/alpha"))
    #expect(memory.sessions[session.id]?.title == "Fix login")
    #expect(memory.sessions[session.id]?.markers == ["ID": "s1"])
    #expect(memory.sessions[session.id]?.endedAt == nil)
    #expect(memory.lineage[child.key]?.session == session.id)
    #expect(memory.lineage[child.key]?.project == Project(root: "/work/alpha"))
  }

  @Test func `a Session that is gone is remembered as ended at the time it was missed`() {
    var memory = Memory.empty
    memory.absorb(observation([root, child], sessions: [session]))

    memory.absorb(observation([child], sessions: [], after: 30, memory: memory))

    #expect(memory.sessions[session.id]?.endedAt == epoch.addingTimeInterval(30))
    #expect(memory.sessions[session.id]?.lastSeenAt == epoch)
  }

  @Test func `a Session seen again is no longer ended`() {
    var memory = Memory.empty
    memory.absorb(observation([root], sessions: [session]))
    memory.absorb(observation([], sessions: [], after: 30))

    memory.absorb(observation([root], sessions: [session], after: 60))

    #expect(memory.sessions[session.id]?.endedAt == nil)
  }

  @Test func `what is remembered about a process is dropped when the process ends`() {
    var memory = Memory.empty
    memory.absorb(observation([root, child], sessions: [session]))

    memory.absorb(observation([root], sessions: [session], after: 30))

    #expect(memory.lineage[child.key] == nil)
    #expect(memory.lastBusyAt[child.key] == nil)
  }

  @Test func `a process counts as busy when first seen and whenever it uses CPU after that`() {
    var memory = Memory.empty
    let first = observation([root, child], sessions: [session])
    memory.absorb(first, usage: Usage(previous: first.snapshot, current: first.snapshot))
    #expect(memory.lastBusyAt[child.key] == epoch)
    #expect(memory.activityAsOf == epoch)

    let working = ProcessRecord.make(101, parent: 100, path: "/opt/bin/node", cpu: .seconds(5))
    let second = observation([root, working], sessions: [session], after: 10)
    memory.absorb(second, usage: Usage(previous: first.snapshot, current: second.snapshot))
    #expect(memory.lastBusyAt[child.key] == epoch.addingTimeInterval(10))

    let third = observation([root, working], sessions: [session], after: 20)
    memory.absorb(third, usage: Usage(previous: second.snapshot, current: third.snapshot))
    #expect(memory.lastBusyAt[child.key] == epoch.addingTimeInterval(10))
  }

  @Test func `without a CPU measurement nothing is recorded about activity`() {
    var memory = Memory.empty

    memory.absorb(observation([root, child], sessions: [session]))

    #expect(memory.lastBusyAt.isEmpty)
    #expect(memory.activityAsOf == nil)
  }

  @Test func `after a gap in observation every followed process counts as busy again`() {
    var memory = Memory.empty
    let first = observation([root, child], sessions: [session])
    memory.absorb(first, usage: Usage(previous: first.snapshot, current: first.snapshot))

    let later = observation([root, child], sessions: [session], after: 600)
    memory.absorb(later, usage: Usage(previous: later.snapshot, current: later.snapshot))

    #expect(memory.lastBusyAt[child.key] == epoch.addingTimeInterval(600))
    #expect(memory.activityAsOf == epoch.addingTimeInterval(600))
  }

  @Test func `Sessions that ended long ago are forgotten`() {
    var memory = Memory.empty
    memory.absorb(observation([root], sessions: [session]))
    memory.absorb(observation([], sessions: [], after: 30))

    memory.forget(sessionsEndedBefore: epoch.addingTimeInterval(60))

    #expect(memory.sessions.isEmpty)
  }
}
