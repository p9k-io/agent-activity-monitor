import AAMCore
import AAMPlatform
import Foundation
import Testing

/// Filing a request writes one row to a scratch store. Nothing is ever ended.
struct CleanupRequestFilerTests {
  let scratch: TemporaryDirectory
  let store: Store
  let root = ProcessRecord.make(100, path: "/opt/bin/claude")
  let server = ProcessRecord.make(101, parent: 100, path: "/opt/bin/node")
  let asker = ProcessRecord.make(102, parent: 100, path: "/opt/bin/aam")
  let stranger = ProcessRecord.make(900, path: "/usr/libexec/other", cwd: nil)

  init() throws {
    scratch = try TemporaryDirectory()
    store = try Store(url: scratch.url.appendingPathComponent("aam.sqlite"))
  }

  var reading: Reading {
    Observer(
      source: ScriptedSource([.of(root, server, asker, stranger)]), adapters: [ClaudeLike()]
    ).observe()
  }

  func filer() -> CleanupRequestFiler {
    CleanupRequestFiler(store: store, ownUser: 501)
  }

  @Test func `a request is stored as pending, with the Session the caller runs in`() throws {
    let filed = try filer().file(
      pids: [101], reason: "not needed", in: reading, caller: 102, now: epoch)

    #expect(filed.request.targets == [server.key])
    #expect(filed.request.requester == SessionID(harness: .claudeCode, value: "s-100"))
    #expect(filed.request.reason == "not needed")
    #expect(filed.request.createdAt == epoch)
    #expect(filed.request.status == .pending)
    #expect(filed.refused.isEmpty)
    #expect(try store.requests() == [filed.request])
  }

  @Test func `a caller outside every Session files a request that names no Session`() throws {
    let filed = try filer().file(pids: [101], reason: "", in: reading, caller: 900, now: epoch)

    #expect(filed.request.requester == nil)
  }

  @Test func `a process named twice is asked for once`() throws {
    let filed = try filer().file(pids: [101, 101], reason: "", in: reading, caller: 102)

    #expect(filed.request.targets == [server.key])
  }

  @Test func `what cannot be asked for is left out and reported`() throws {
    let filed = try filer().file(pids: [101, 4242], reason: "", in: reading, caller: 102)

    #expect(filed.request.targets == [server.key])
    #expect(filed.refused.map(\.reason) == [.gone])
  }

  @Test func `a request with nothing left to ask for is refused and not stored`() throws {
    // Seen by a user who owns none of the processes.
    let foreign = CleanupRequestFiler(store: store, ownUser: 0)

    #expect(throws: CleanupRequestFiler.Refusal.nothingToAsk([.notYours, .gone])) {
      try foreign.file(pids: [101, 4242], reason: "", in: reading, caller: 102)
    }
    #expect(try store.requests().isEmpty)
  }

  @Test func `too many processes in one request are refused`() throws {
    let many = Array(repeating: Int32(101), count: CleanupRequestFiler.processLimit + 1)

    #expect(throws: CleanupRequestFiler.Refusal.tooManyProcesses) {
      try filer().file(pids: many, reason: "", in: reading, caller: 102)
    }
  }

  @Test func `no more requests are taken while too many wait for a decision`() throws {
    for index in 0..<CleanupRequestFiler.pendingLimit {
      try store.add(
        CleanupRequest(
          id: "p\(index)", createdAt: epoch, requester: nil, reason: "", targets: [server.key]))
    }

    #expect(throws: CleanupRequestFiler.Refusal.tooManyPending) {
      try filer().file(pids: [101], reason: "", in: reading, caller: 102)
    }
    #expect(try store.requests().count == CleanupRequestFiler.pendingLimit)
  }

  @Test func `every refusal says what to do about it`() {
    #expect(
      CleanupRequestFiler.Refusal.nothingToAsk([.gone, .notYours]).description
        == "Nothing to ask for: there is no such process any more; it belongs to another user.")
    #expect(
      CleanupRequestFiler.Refusal.tooManyProcesses.description
        == "A Cleanup request takes at most 100 processes.")
    #expect(
      CleanupRequestFiler.Refusal.tooManyPending.description
        == "50 Cleanup requests already wait for a decision in the app. "
        + "Ask again once they are decided.")
  }
}
