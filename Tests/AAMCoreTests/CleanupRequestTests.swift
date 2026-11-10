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

  @Test func `a reason is kept to one line without control characters`() {
    let reason = request(reason: "first\nsecond\tthird\u{1B}[31m red\u{07}").reason

    #expect(reason == "first second third[31m red")
  }
}
