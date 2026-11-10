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
    let filed: (request: CleanupRequest, refused: [CleanupPlan.Refusal])
    do {
      filed = try CleanupRequestFiler(store: store).file(pids: pids, reason: reason, in: reading)
    } catch let refusal as CleanupRequestFiler.Refusal {
      throw failure("aam: \(refusal)")
    }

    if output.json {
      try printJSON(RequestRow(filed.request, refused: filed.refused))
    } else {
      print(
        "Filed Cleanup request \(filed.request.id) for \(filed.request.targets.count) processes.")
      for refusal in filed.refused {
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
