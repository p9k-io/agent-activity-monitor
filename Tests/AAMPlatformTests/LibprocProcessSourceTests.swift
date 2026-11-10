import AAMCore
import AAMPlatform
import Darwin
import Foundation
import Testing

struct LibprocProcessSourceTests {
  let source = LibprocProcessSource(markerNames: ["AAM_TEST_MARKER"])

  @Test func `the current process is listed with its own facts`() throws {
    let me = try #require(source.processes().first { $0.pid == getpid() })

    #expect(me.parentPID == getppid())
    #expect(me.userID == getuid())
    #expect(me.residentBytes > 0)
    #expect(!me.executablePath.isEmpty)
    #expect(!me.isZombie)
    #expect(me.startedAt < Date())
    #expect(me.startedAt > Date().addingTimeInterval(-3600))
  }

  @Test func `CPU time is reported in real time, not in machine ticks`() throws {
    let before = try #require(source.record(for: getpid()))
    let deadline = ContinuousClock.now + .milliseconds(300)
    var value = 0.0
    while ContinuousClock.now < deadline {
      value += sin(value + 1)
    }
    let after = try #require(source.record(for: getpid()))

    let spent = after.cpuTime - before.cpuTime
    #expect(spent > .milliseconds(150))
    #expect(spent < .seconds(8))
  }

  @Test func `a child is listed under its parent with its arguments and directory`() throws {
    let scratch = try TemporaryDirectory()
    let child = try Helper.sleeping(seconds: 30, in: scratch.url)
    defer { child.terminate() }

    let record = try #require(source.record(for: child.processIdentifier))

    #expect(record.parentPID == getpid())
    #expect(record.name == "aam-test-helper")
    #expect(record.arguments.suffix(2) == ["sleep", "30"])
    #expect(record.workingDirectory == scratch.url.path)
  }

  @Test func `a marker in the environment of a non-Apple binary is read, other variables are not`()
    throws
  {
    let child = try Helper.sleeping(
      environment: ["AAM_TEST_MARKER": "session-1", "SOMETHING_ELSE": "ignored"])
    defer { child.terminate() }

    let record = try #require(source.record(for: child.processIdentifier))

    #expect(record.markers == ["AAM_TEST_MARKER": "session-1"])
  }

  @Test func `a process that has ended and been collected has no record`() throws {
    let child = try Helper.sleeping(seconds: 0)
    child.waitUntilExit()

    #expect(source.record(for: child.processIdentifier) == nil)
  }

  @Test func `a child that has ended but was not collected is a zombie`() throws {
    var pid: pid_t = 0
    let path = Helper.url.path
    let arguments: [UnsafeMutablePointer<CChar>?] = [
      strdup(path), strdup("sleep"), strdup("0"), nil,
    ]
    defer {
      for argument in arguments {
        free(argument)
      }
    }
    #expect(posix_spawn(&pid, path, nil, nil, arguments, nil) == 0)
    defer {
      var status: Int32 = 0
      waitpid(pid, &status, 0)
    }

    var record: ProcessRecord?
    let deadline = ContinuousClock.now + .seconds(3)
    repeat {
      record = source.record(for: pid)
      usleep(20_000)
    } while record?.isZombie != true && ContinuousClock.now < deadline

    #expect(record?.isZombie == true)
  }
}

struct SystemProcessSourceTests {
  @Test func `processes of other users come along with the current user's`() throws {
    let snapshot = SystemProcessSource(markerNames: []).snapshot()

    let launchd = try #require(snapshot.processes.first { $0.pid == 1 })
    #expect(launchd.userID == 0)
    #expect(snapshot.processes.contains { $0.pid == getpid() && $0.workingDirectory != nil })
  }

  @Test func `no process is listed twice`() {
    let pids = SystemProcessSource(markerNames: []).snapshot().processes.map(\.pid)

    #expect(Set(pids).count == pids.count)
  }
}
