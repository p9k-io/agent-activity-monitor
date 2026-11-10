import AAMCore
import AAMPlatform
import Darwin
import Foundation
import Testing

struct KernelProcessTableTests {
  @Test func `every process is listed with its identity, whoever owns it`() throws {
    let table = KernelProcessTable.read()

    let me = try #require(table.first { $0.pid == getpid() })
    #expect(me.parentPID == getppid())
    #expect(me.userID == getuid())
    #expect(me.startedAt < Date())
    #expect(me.startedAt > Date().addingTimeInterval(-3600))
    #expect(!me.isZombie)
    #expect(table.first { $0.pid == 1 }?.userID == 0)
  }
}

struct SystemProcessSourceTests {
  let source = SystemProcessSource(markerNames: ["AAM_TEST_MARKER"])

  @Test func `the current process is listed with its own facts`() throws {
    let me = try #require(source.snapshot().processes.first { $0.pid == getpid() })

    #expect(me.parentPID == getppid())
    #expect(me.userID == getuid())
    #expect(me.residentBytes > 0)
    #expect(!me.executablePath.isEmpty)
    #expect(me.workingDirectory != nil)
    #expect(!me.isZombie)
  }

  /// The CPU time this process has used, as the system reports it to the process itself.
  func ownCPUTime() -> Duration {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return .seconds(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
      + .microseconds(Int64(usage.ru_utime.tv_usec) + Int64(usage.ru_stime.tv_usec))
  }

  @Test func `CPU time is reported in real time, not in machine ticks`() throws {
    let before = try #require(source.record(for: getpid()))
    let referenceBefore = ownCPUTime()
    let deadline = ContinuousClock.now + .milliseconds(300)
    var value = 0.0
    while ContinuousClock.now < deadline {
      value += sin(value + 1)
    }
    let after = try #require(source.record(for: getpid()))
    let reference = ownCPUTime() - referenceBefore

    // Both clocks count the same work, so they agree whatever else the machine is doing. A
    // mistake in units would be off by a factor of forty.
    let spent = after.cpuTime - before.cpuTime
    #expect(reference > .milliseconds(10))
    #expect(spent > reference / 2)
    #expect(spent < reference * 2)
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
    #expect(source.snapshot().processes.first { $0.pid == pid }?.isZombie == true)
  }

  @Test func `processes of other users come along with their path, memory and CPU time`() throws {
    let launchd = try #require(source.snapshot().processes.first { $0.pid == 1 })

    #expect(launchd.userID == 0)
    #expect(launchd.executablePath == "/sbin/launchd")
    #expect(launchd.cpuTime > .zero)
    #expect(launchd.residentBytes > 0)
  }

  @Test func `no process is listed twice`() {
    let pids = source.snapshot().processes.map(\.pid)

    #expect(Set(pids).count == pids.count)
  }

  @Test func `what is known about other users' processes is kept between refreshes`() throws {
    let full = try #require(source.snapshot().processes.first { $0.pid == 1 })

    let light = try #require(
      source.snapshot(refreshingOtherUsers: false).processes.first { $0.pid == 1 })

    #expect(light.cpuTime == full.cpuTime)
    #expect(light.executablePath == full.executablePath)
  }

  @Test func `a process that replaces its program is read again`() throws {
    let (child, trigger) = try Helper.becomingSleep(seconds: 30)
    defer { child.terminate() }
    let pid = child.processIdentifier
    #expect(source.snapshot().processes.first { $0.pid == pid }?.name == "aam-test-helper")

    trigger.fileHandleForWriting.write(Data([1]))
    var record: ProcessRecord?
    let deadline = ContinuousClock.now + .seconds(3)
    repeat {
      usleep(20_000)
      record = source.snapshot(refreshingOtherUsers: false).processes.first { $0.pid == pid }
    } while record?.name != "sleep" && ContinuousClock.now < deadline

    #expect(record?.executablePath == "/bin/sleep")
    #expect(record?.arguments == ["/bin/sleep", "30"])
  }
}
