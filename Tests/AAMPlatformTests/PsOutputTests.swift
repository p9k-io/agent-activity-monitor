import AAMPlatform
import Testing

struct PsOutputTests {
  // Synthetic output in the shape of: ps -axo pid=,rss=,time=,comm=
  let output = """
       10   2048   1:02.50 /usr/libexec/daemon
       20      0   0:00.00 <defunct>
       30   4096 1036:01.89 /Applications/Some App.app/Contents/MacOS/Some App
       40    512 2-03:04:05.50 /usr/sbin/veteran
    this line is not a process
    """

  @Test func `each well-formed line gives the facts of one process and the rest is skipped`() {
    #expect(PsOutput.parse(output).keys.sorted() == [10, 20, 30, 40])
  }

  @Test func `memory, CPU time and the executable path are read`() throws {
    let daemon = try #require(PsOutput.parse(output)[10])

    #expect(daemon.residentBytes == 2048 * 1024)
    #expect(daemon.cpuTime == .milliseconds(62_500))
    #expect(daemon.executablePath == "/usr/libexec/daemon")
  }

  @Test func `an executable path with spaces and a long CPU time survive`() throws {
    let app = try #require(PsOutput.parse(output)[30])

    #expect(app.executablePath == "/Applications/Some App.app/Contents/MacOS/Some App")
    #expect(app.cpuTime == .milliseconds((1036 * 60 + 1) * 1000 + 890))
  }

  @Test func `CPU time that runs into days is read`() throws {
    let veteran = try #require(PsOutput.parse(output)[40])

    // Two days, three hours, four minutes and five and a half seconds.
    #expect(veteran.cpuTime == .milliseconds(183_845_500))
  }
}
