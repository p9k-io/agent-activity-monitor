import AAMCore
import Testing

/// The reason of a Cleanup request is written by whoever files it, so it is treated as text
/// from outside.
struct CleanupRequestTests {
  func request(reason: String) -> CleanupRequest {
    CleanupRequest(id: "r1", createdAt: epoch, requester: nil, reason: reason, targets: [])
  }

  @Test func `a reason longer than the limit is cut`() {
    #expect(request(reason: String(repeating: "a", count: 800)).reason.count == 500)
  }

  @Test func `characters that break a line or reorder text are taken out of a reason`() {
    // A line separator, a right-to-left override and an isolate.
    let reason = request(reason: "first\u{2028}second\u{2029}th\u{202E}i\u{2066}rd").reason

    #expect(reason == "first second third")
  }

  @Test func `the limit of a reason counts what is stored, not what is seen`() {
    // One visible character made of a letter and two thousand accents.
    let stacked = "e" + String(repeating: "\u{301}", count: 2000)

    #expect(request(reason: stacked).reason.unicodeScalars.count == 500)
  }

  @Test func `a reason is kept to one line without control characters`() {
    let reason = request(reason: "first\nsecond\tthird\u{1B}[31m red\u{07}").reason

    #expect(reason == "first second third[31m red")
  }
}
