import AAMCleanup
import AAMCore
import AAMPlatform
import Foundation

/// A Cleanup a person is looking at: proposed, being carried out, or finished.
struct CleanupFlow: Identifiable, Equatable {
  enum Stage: Equatable {
    case proposed
    case running
    case finished(CleanupReport)
  }

  let proposal: CleanupProposal
  var stage = Stage.proposed

  var id: String { proposal.id }
}

/// What a Cleanup did.
enum CleanupReport: Equatable {
  case processes(CleanupRequest.Outcome)
  case simulator(shutDown: Bool)
}

extension AppModel {
  var pendingRequests: [CleanupRequest] {
    requests.filter { $0.status == .pending }
  }

  /// Shows a proposal for a person to confirm. Nothing is ended by this.
  func propose(_ make: (CleanupProposer) -> CleanupProposal?) {
    guard let proposer, let proposal = make(proposer) else { return }
    cleanup = CleanupFlow(proposal: proposal)
  }

  /// Carries out the Cleanup that is on show. Call it only from the button a person confirms
  /// the Cleanup with.
  func carryOutCleanup() async {
    guard let flow = cleanup, flow.stage == .proposed, flow.proposal.canProceed else { return }
    cleanup?.stage = .running
    let proposal = flow.proposal
    let report: CleanupReport
    switch proposal.means {
    case .endProcesses:
      report = .processes(await Self.end(proposal.asked, with: terminator))
    case .shutDownSimulator(let device):
      report = .simulator(shutDown: await Self.shutDown(device))
    }
    if var request = proposal.request, case .processes(let outcome) = report {
      request.status = .done
      request.decidedAt = Date()
      request.outcome = outcome
      record(request)
    }
    if cleanup?.id == flow.id {
      cleanup?.stage = .finished(report)
    }
    run()
  }

  /// Turns a Cleanup request down. Nothing is ended.
  func deny(_ request: CleanupRequest) {
    var decided = request
    decided.status = .denied
    decided.decidedAt = Date()
    record(decided)
  }

  /// Where CPU time went over the last days, or nil when the store cannot be read.
  func usageReport(days: Int) async -> UsageReport? {
    #if DEBUG
      if isDemo { return DemoData.report }
    #endif
    guard let store else { return nil }
    return await Self.report(from: store, since: Date().addingTimeInterval(-Double(days) * 86_400))
  }

  @concurrent
  nonisolated private static func report(from store: Store, since start: Date) async
    -> UsageReport?
  {
    try? store.usageReport(since: start)
  }

  // Ending processes waits for them to exit and shutting a simulator down waits for a tool,
  // so both are kept off the main thread.

  @concurrent
  nonisolated private static func end(
    _ keys: [ProcessRecord.Key], with terminator: Terminator
  ) async -> CleanupRequest.Outcome {
    await terminator.end(keys).outcome
  }

  @concurrent
  nonisolated private static func shutDown(_ device: String) async -> Bool {
    SimulatorControl().shutDown(device: device)
  }
}
