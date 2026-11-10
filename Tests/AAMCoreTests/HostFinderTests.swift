import AAMCore
import Foundation
import Testing

struct HostFinderTests {
  let app = ProcessRecord.make(
    10, path: "/Applications/Example Terminal.app/Contents/MacOS/Example Terminal")
  let shell = ProcessRecord.make(20, parent: 10, path: "/bin/zsh", terminal: true)
  let root = ProcessRecord.make(100, parent: 20, path: "/opt/bin/claude", terminal: true)

  func places(_ processes: [ProcessRecord], root: ProcessRecord) -> [SessionID: HostPlace] {
    HostFinder.places(of: [Session.make("s1", root: root)], in: ProcessTree(processes))
  }

  @Test func `the Host of a Session is the application its terminal runs in`() throws {
    let place = try #require(places([app, shell, root], root: root).values.first)

    #expect(place.host == "Example Terminal")
    #expect(place.hostPID == 10)
    #expect(place.location == nil)
    #expect(place.label == "Example Terminal")
  }

  @Test func `a helper inside an application leads to the application itself`() throws {
    // An editor runs its terminals in a helper that lives inside its own bundle.
    let editor = ProcessRecord.make(
      10, path: "/Applications/Example Editor.app/Contents/MacOS/Example Editor")
    let helper = ProcessRecord.make(
      15, parent: 10,
      path: "/Applications/Example Editor.app/Contents/Frameworks/"
        + "Editor Helper (Plugin).app/Contents/MacOS/Editor Helper (Plugin)")
    let nested = ProcessRecord.make(100, parent: 15, path: "/opt/bin/codex", terminal: true)

    let place = try #require(places([editor, helper, nested], root: nested).values.first)

    #expect(place.host == "Example Editor")
    #expect(place.hostPID == 10)
  }

  @Test func `a Session that no application started has no Host`() {
    let daemon = ProcessRecord.make(5, path: "/usr/sbin/sshd")
    let remote = ProcessRecord.make(100, parent: 5, path: "/opt/bin/claude", terminal: true)

    #expect(places([daemon, remote], root: remote).isEmpty)
  }

  @Test func `a place says where it is in the Host's own words when the Host tells`() {
    let place = HostPlace(
      host: "Example Terminal", hostPID: 10, location: "Shop › Checkout", reference: [:])

    #expect(place.label == "Example Terminal › Shop › Checkout")
  }
}
