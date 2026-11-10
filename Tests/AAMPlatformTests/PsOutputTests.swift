import AAMCore
import AAMPlatform
import Foundation
import Testing

struct PsOutputTests {
  let utc = TimeZone(identifier: "UTC")!

  // Synthetic output in the shape of:
  // ps -axo pid=,ppid=,pgid=,uid=,rss=,time=,state=,tty=,lstart=,comm=
  let output = """
       10     1    10     0   2048   1:02.50 Ss   ??       Mon Jan  5 08:00:00 2026     /usr/libexec/daemon
       20    10    20   501      0   0:00.00 Z+   ttys001  Mon Jan  5 09:30:15 2026     <defunct>
       30     1    30   501   4096 1036:01.89 R    ??       Tue Jan  6 10:00:00 2026     /Applications/Some App.app/Contents/MacOS/Some App
    this line is not a process
    """

  func parsed() -> [ProcessRecord] {
    PsOutput.parse(output, timeZone: utc)
  }

  @Test func `each well-formed line becomes a process and the rest is skipped`() {
    #expect(parsed().map(\.pid) == [10, 20, 30])
  }

  @Test func `identifiers, owner, memory and CPU time are read`() throws {
    let daemon = try #require(parsed().first)

    #expect(daemon.parentPID == 1)
    #expect(daemon.groupID == 10)
    #expect(daemon.userID == 0)
    #expect(daemon.residentBytes == 2048 * 1024)
    #expect(daemon.cpuTime == .milliseconds(62_500))
    #expect(daemon.executablePath == "/usr/libexec/daemon")
    #expect(!daemon.isZombie)
    #expect(!daemon.hasTerminal)
  }

  @Test func `the start time is read in the given time zone`() throws {
    let daemon = try #require(parsed().first)
    let expected = try #require(
      Calendar(identifier: .gregorian).date(
        from: DateComponents(
          timeZone: utc, year: 2026, month: 1, day: 5, hour: 8, minute: 0, second: 0)))

    #expect(daemon.startedAt == expected)
  }

  @Test func `a zombie on a terminal is recognised`() throws {
    let zombie = try #require(parsed().first { $0.pid == 20 })

    #expect(zombie.isZombie)
    #expect(zombie.hasTerminal)
  }

  @Test func `an executable path with spaces and a long CPU time survive`() throws {
    let app = try #require(parsed().last)

    #expect(app.executablePath == "/Applications/Some App.app/Contents/MacOS/Some App")
    #expect(app.cpuTime == .milliseconds((1036 * 60 + 1) * 1000 + 890))
  }
}
