import AAMCleanup
import AAMCore
import AAMPlatform
import Darwin
import Foundation
import Testing

/// Every process these tests end is one they started themselves.
struct TerminatorTests {
  let source = SystemProcessSource(markerNames: [])

  func terminator(grace: Duration = .seconds(2)) -> Terminator {
    Terminator(source: source, grace: grace)
  }

  func key(of process: Process) throws -> ProcessRecord.Key {
    try #require(source.record(for: process.processIdentifier)).key
  }

  @Test func `a process asked to end exits and is reported as ended`() async throws {
    let helper = try Helper.start("sleep")
    defer { helper.terminate() }
    let key = try key(of: helper)

    let result = await terminator().end([key])

    #expect(result.ended == [key])
    #expect(result.killed.isEmpty)
    #expect(result.survived.isEmpty)
    helper.waitUntilExit()
    #expect(helper.terminationReason == .uncaughtSignal)
    #expect(helper.terminationStatus == SIGTERM)
  }

  @Test func `a process that ignores the request is ended by force after the grace period`()
    async throws
  {
    let helper = try Helper.start("ignore-term")
    defer { kill(helper.processIdentifier, SIGKILL) }
    // Give the helper a moment to start ignoring the signal.
    try await Task.sleep(for: .milliseconds(300))
    let key = try key(of: helper)

    let result = await terminator(grace: .milliseconds(400)).end([key])

    #expect(result.ended.isEmpty)
    #expect(result.killed == [key])
    helper.waitUntilExit()
    #expect(helper.terminationStatus == SIGKILL)
  }

  @Test func `what the target started ends with it`() async throws {
    let helper = try Helper.start("tree")
    defer { helper.terminate() }
    try await Task.sleep(for: .milliseconds(300))
    let parent = try key(of: helper)
    let child = try #require(
      source.snapshot(refreshingOtherUsers: false).processes
        .first { $0.parentPID == helper.processIdentifier })
    defer { kill(child.pid, SIGKILL) }

    let result = await terminator().end([parent])

    #expect(Set(result.ended) == [parent, child.key])
    #expect(source.record(for: child.pid).map { !$0.isZombie } != true)
  }

  @Test func `an identifier that no longer names the same process is never signalled`()
    async throws
  {
    let helper = try Helper.start("sleep")
    defer { helper.terminate() }
    let real = try key(of: helper)
    let stale = ProcessRecord.Key(pid: real.pid, startedAt: real.startedAt.addingTimeInterval(-60))

    let result = await terminator().end([stale])

    #expect(result.refused == [CleanupPlan.Refusal(process: stale, reason: .gone)])
    #expect(result.ended.isEmpty)
    #expect(helper.isRunning)
  }

  @Test func `the process doing the Cleanup refuses to end itself`() async throws {
    let me = try #require(source.record(for: getpid())).key

    let result = await terminator().end([me])

    #expect(result.refused == [CleanupPlan.Refusal(process: me, reason: .protected)])
  }
}

struct SimulatorControlTests {
  @Test func `a simulator is shut down by its device identifier`() {
    nonisolated(unsafe) var commands: [[String]] = []
    let control = SimulatorControl { arguments in
      commands.append(arguments)
      return 0
    }

    let done = control.shutDown(device: "AAAAAAAA-1111-4222-8333-BBBBBBBBBBBB")

    #expect(done)
    #expect(commands == [["simctl", "shutdown", "AAAAAAAA-1111-4222-8333-BBBBBBBBBBBB"]])
  }

  @Test func `anything that is not a device identifier is refused without running a command`() {
    nonisolated(unsafe) var ran = false
    let control = SimulatorControl { _ in
      ran = true
      return 0
    }

    #expect(!control.shutDown(device: "booted; rm -rf /"))
    #expect(!ran)
  }

  @Test func `a failed shutdown is reported`() {
    #expect(!SimulatorControl { _ in 1 }.shutDown(device: "AAAAAAAA-1111-4222-8333-BBBBBBBBBBBB"))
  }
}
