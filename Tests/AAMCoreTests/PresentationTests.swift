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

  @Test func `a time that cannot be real does not break the wording`() {
    let absurd = Date(timeIntervalSince1970: 1e300)

    #expect(Format.span(from: epoch, to: absurd) == "36500d 0h")
    #expect(Format.span(from: absurd, to: epoch) == "0s")
    #expect(Format.cpuTime(1e300) == "876000h 0m")
    #expect(Format.cpuTime(-.infinity) == "0s")
    #expect(Format.cpuTime(.nan) == "0s")
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

  @Test(arguments: [
    (CleanupRequest.Outcome(ended: 5, endedByForce: 0, survived: 0, refused: 0), "5 exited."),
    (
      CleanupRequest.Outcome(ended: 5, endedByForce: 1, survived: 2, refused: 3),
      "5 exited, 1 ended by force, 2 still running, 3 left alone."
    ),
    (CleanupRequest.Outcome(ended: 0, endedByForce: 0, survived: 0, refused: 2), "2 left alone."),
    (
      CleanupRequest.Outcome(ended: 0, endedByForce: 0, survived: 0, refused: 0),
      "Nothing was ended."
    ),
  ])
  func `what a Cleanup did is told in the numbers that are not zero`(
    outcome: CleanupRequest.Outcome, expected: String
  ) {
    #expect(outcome.text == expected)
  }

  @Test func `why a process is left alone reads after its identifier`() {
    #expect(CleanupPlan.Reason.gone.explanation == "there is no such process any more")
    #expect(CleanupPlan.Reason.notYours.explanation == "it belongs to another user")
    #expect(CleanupPlan.Reason.protected.explanation == "it must never be ended")
    #expect(
      CleanupPlan.Reason.zombie.explanation
        == "it has ended already and waits to be collected by its parent")
  }

  @Test func `kinds and states have names a person reads`() {
    #expect(HarnessID.claudeCode.label == "Claude Code")
    #expect(HarnessID.codex.label == "Codex")
    #expect(HarnessID(rawValue: "other-tool").label == "other-tool")
    #expect(StaleFinding.Kind.ownerlessLeftover.label == "Ownerless leftover")
    #expect(StaleFinding.Kind.idleDevServer.label == "Idle dev server")
    #expect(SessionState.background.label == "Background work")
    #expect(ProcessKind.mcpServer.label == "MCP server")
    #expect(Evidence.remembered.label == "Remembered")
  }
}
