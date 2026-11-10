import AAMCore
import AAMPlatform
import ArgumentParser
import Foundation

struct RequestCleanup: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "request-cleanup",
    abstract: "Ask for processes to be cleaned up. A person decides in the app.",
    discussion: """
      Nothing is ended by this command. The request waits in the Agent Activity Monitor app, \
      where a person approves or denies it. What each process started is cleaned up with it.
      """
  )

  @Argument(help: "The identifiers of the processes that are no longer needed.")
  var pids: [Int32]

  @Option(name: .long, help: "Why they are no longer needed. Shown to the person who decides.")
  var reason = ""

  @OptionGroup var output: OutputOptions

  func run() throws {
    guard let store = try? Store(url: Store.defaultURL) else {
      throw failure("aam: the store at \(Store.defaultURL.path) cannot be opened.")
    }
    let reading = Monitor(store: store).look().observation
    // A process that is not there is asked for by a key nothing can match, so that the
    // planner reports it as gone.
    let keys = pids.map { pid in
      reading.snapshot.processes.first { $0.pid == pid }?.key
        ?? ProcessRecord.Key(pid: pid, startedAt: .distantPast)
    }
    let plan = CleanupPlanner(ownUser: getuid(), protected: [])
      .plan(for: keys, in: reading.snapshot, includingDescendants: false)
    guard !plan.targets.isEmpty else {
      let reasons = plan.refused.map { "\($0.process.pid): \($0.reason.explanation)" }
      throw failure("aam: nothing to ask for.\n" + reasons.joined(separator: "\n"))
    }

    let request = CleanupRequest(
      id: String(UUID().uuidString.lowercased().prefix(8)),
      createdAt: Date(),
      requester: reading.inventory.session(owning: getpid())?.session.id,
      reason: reason,
      targets: plan.targets.map(\.key))
    try store.add(request)

    if output.json {
      try printJSON(RequestRow(request, refused: plan.refused))
    } else {
      print("Filed Cleanup request \(request.id) for \(request.targets.count) processes.")
      for refusal in plan.refused {
        print("Left out \(refusal.process.pid): \(refusal.reason.explanation)")
      }
      print("A person decides in the Agent Activity Monitor app. See it with: aam requests")
    }
  }

  private func failure(_ message: String) -> ExitCode {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    return ExitCode(1)
  }
}

struct Requests: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "List Cleanup requests and what was decided about them.")

  @OptionGroup var output: OutputOptions

  func run() throws {
    let requests = (try? Store(url: Store.defaultURL).requests()) ?? []
    let report = RequestsReport(requests: requests.map { RequestRow($0, refused: []) })
    if output.json {
      try printJSON(report)
    } else {
      print(report.table(now: Date()))
    }
  }
}
