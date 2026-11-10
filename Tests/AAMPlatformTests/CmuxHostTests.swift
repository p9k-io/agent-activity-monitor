import AAMCore
import AAMPlatform
import Foundation
import Testing

struct CmuxHostTests {
  let root = ProcessRecord.make(100, path: "/opt/bin/claude")
  var session: Session {
    Session(
      id: SessionID(harness: .claudeCode, value: "s1"), root: root.key,
      project: Project(root: "/work/alpha"), workingDirectory: "/work/alpha", title: nil,
      state: .idle, lastActivityAt: nil, resumeCommand: nil, markers: [:])
  }
  let generic = HostPlace(host: "cmux", hostPID: 10, location: nil, reference: [:])

  /// The layout as the Host reports it: one window, one group of panels, two panels.
  let tree = """
    {"windows": [{"workspaces": [{"id": "W-1", "title": "Shop", "panes": [{"surfaces": [
      {"id": "S-1", "title": "checkout", "type": "terminal"},
      {"id": "S-2", "title": "https://example.test/?token=abc", "type": "browser"}
    ]}]}]}]}
    """

  /// Counts how often the layout was asked for and notes what the Host was told to do.
  final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var asked = 0
    private var told: [[String]] = []
    var timesAsked: Int { lock.withLock { asked } }
    var commands: [[String]] { lock.withLock { told } }
    func ask() { lock.withLock { asked += 1 } }
    func tell(_ arguments: [String]) { lock.withLock { told.append(arguments) } }
  }

  func host(
    environment: [Int32: [String: String]] = [
      100: ["CMUX_WORKSPACE_ID": "W-1", "CMUX_SURFACE_ID": "S-1"]
    ],
    tree: String? = nil, recorder: Recorder = Recorder(),
    now: @escaping @Sendable () -> Date = { epoch }
  ) -> CmuxHost {
    let layout = tree ?? self.tree
    return CmuxHost(
      environment: { pid, _ in environment[pid] ?? [:] },
      run: { arguments in
        if arguments.contains("tree") {
          recorder.ask()
          return Data(layout.utf8)
        }
        recorder.tell(arguments)
        return Data()
      },
      now: now)
  }

  @Test func `a Session in the Host is told by the names of where its terminal is`() throws {
    let places = host().refine([session.id: generic], sessions: [session])

    let place = try #require(places[session.id])
    #expect(place.location == "Shop › checkout")
    #expect(place.label == "cmux › Shop › checkout")
    #expect(place.hostPID == 10)
  }

  @Test func `a Session whose terminal is not the Host's keeps the place it had`() {
    let elsewhere = HostPlace(host: "Example Terminal", hostPID: 10, location: nil, reference: [:])

    let places = host(environment: [:]).refine([session.id: elsewhere], sessions: [session])

    #expect(places[session.id] == elsewhere)
  }

  @Test(arguments: ["this is not JSON", "{\"windows\": 7}", "{}"])
  func `a layout that cannot be read leaves the place as it was`(layout: String) {
    let places = host(tree: layout).refine([session.id: generic], sessions: [session])

    #expect(places[session.id] == generic)
  }

  @Test func `the layout is asked for once in a while, not on every look`() {
    let recorder = Recorder()
    let clock = Recorder()
    let host = host(recorder: recorder) {
      // Ten seconds pass between two looks.
      clock.ask()
      return epoch.addingTimeInterval(Double(clock.timesAsked) * 10)
    }

    for _ in 0..<5 {
      _ = host.refine([session.id: generic], sessions: [session])
    }

    #expect(recorder.timesAsked == 1)
  }

  @Test func `nothing is asked when no Session lives in the Host`() {
    let recorder = Recorder()

    _ = host(environment: [:], recorder: recorder).refine(
      [session.id: generic], sessions: [session])

    #expect(recorder.timesAsked == 0)
  }

  @Test func `showing a place selects its group of panels and then the panel`() throws {
    let recorder = Recorder()
    let host = host(recorder: recorder)
    let place = try #require(host.refine([session.id: generic], sessions: [session])[session.id])

    #expect(host.show(place))
    #expect(
      recorder.commands == [
        ["select-workspace", "--workspace", "W-1"],
        ["focus-panel", "--panel", "S-1", "--workspace", "W-1"],
      ])
  }

  @Test func `a place the Host did not describe cannot be shown by it`() {
    let recorder = Recorder()

    #expect(!host(recorder: recorder).show(generic))
    #expect(recorder.commands.isEmpty)
  }
}
