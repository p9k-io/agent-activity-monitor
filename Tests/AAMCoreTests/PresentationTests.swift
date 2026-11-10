import AAMCore
import Foundation
import Testing

struct PresentationTests {
  static let spans: [(Double, String)] = [
    (0, "0s"), (59, "59s"), (60, "1m"), (3599, "59m"), (3600, "1h 0m"), (18_420, "5h 7m"),
    (86_400, "1d 0h"), (273_659, "3d 4h"),
  ]

  @Test(arguments: spans)
  func `a span of time is told in its two largest units`(seconds: Double, expected: String) {
    #expect(Format.span(from: epoch, to: epoch.addingTimeInterval(seconds)) == expected)
  }

  @Test func `a span that would run backwards is zero`() {
    #expect(Format.span(from: epoch.addingTimeInterval(10), to: epoch) == "0s")
  }

  @Test func `CPU use keeps one decimal, written the way the person's region writes numbers`() {
    #expect(Format.cpu(518.24, locale: Locale(identifier: "en_US")) == "518.2 %")
    #expect(Format.cpu(518.24, locale: Locale(identifier: "cs_CZ")) == "518,2 %")
    #expect(Format.cpu(0, locale: Locale(identifier: "en_US")) == "0.0 %")
  }

  @Test func `every reason reads as a sentence fragment a person can act on`() {
    let now = epoch.addingTimeInterval(3 * 3600)
    let session = SessionID(harness: .claudeCode, value: "s1")

    #expect(StaleFinding.Reason.sessionIdle(since: epoch).text(now: now) == "no activity for 3h 0m")
    #expect(
      StaleFinding.Reason.orphan(formerSession: session, since: epoch).text(now: now)
        == "its Session ended 3h 0m ago")
    #expect(
      StaleFinding.Reason.orphan(formerSession: nil, since: nil).text(now: now)
        == "its Session is gone")
    #expect(
      StaleFinding.Reason.zombie(parent: 42).text(now: now)
        == "ended, waiting to be collected by 42")
    #expect(StaleFinding.Reason.olderDuplicate(of: 77).text(now: now) == "older copy of 77")
    #expect(
      StaleFinding.Reason.projectQuiet(since: epoch).text(now: now)
        == "nothing worked in the Project for 3h 0m")
    #expect(StaleFinding.Reason.serverIdle(since: epoch).text(now: now) == "no CPU use for 3h 0m")
  }

  @Test func `kinds and states have names a person reads`() {
    #expect(StaleFinding.Kind.ownerlessLeftover.label == "Ownerless leftover")
    #expect(StaleFinding.Kind.idleDevServer.label == "Idle dev server")
    #expect(SessionState.background.label == "Background work")
    #expect(ProcessKind.mcpServer.label == "MCP server")
    #expect(Evidence.remembered.label == "Remembered")
  }
}
