import AAMCore
import SwiftUI

/// Asks a person to confirm a Cleanup, then shows what it did.
///
/// Everything here that comes from a process or from whoever filed a request is shown as plain
/// text, never interpreted.
struct CleanupSheet: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    // Read from the model, so that the sheet follows the Cleanup from proposed to finished.
    if let flow = model.cleanup {
      VStack(alignment: .leading, spacing: 14) {
        header(flow)
        cautions(flow.proposal)
        targets(flow.proposal)
        leftAlone(flow.proposal)
        resume(flow.proposal)
        Divider()
        footer(flow)
      }
      .padding(20)
      .frame(width: 600)
      .interactiveDismissDisabled(flow.stage == .running)
    }
  }

  private func header(_ flow: CleanupFlow) -> some View {
    let proposal = flow.proposal
    return VStack(alignment: .leading, spacing: 6) {
      // The title is a question, so it gives way once the answer has been carried out.
      Text(verbatim: flow.stage == .proposed ? proposal.title : "Cleanup")
        .font(.title3.weight(.semibold))
      Text(verbatim: proposal.message)
        .foregroundStyle(.secondary)
      if let request = proposal.request {
        Text(
          verbatim: request.reason.isEmpty
            ? "No reason was given." : "Reason given: \(request.reason)"
        )
        .foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder
  private func cautions(_ proposal: CleanupProposal) -> some View {
    ForEach(proposal.cautions, id: \.self) { caution in
      Label {
        Text(verbatim: caution)
          .fixedSize(horizontal: false, vertical: true)
      } icon: {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
      }
    }
  }

  private func targets(_ proposal: CleanupProposal) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(summary(proposal))
        .font(.subheadline.weight(.semibold))
      if proposal.canProceed {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 4) {
            ForEach(proposal.targets) { target in
              TargetRow(target: target)
            }
          }
          .padding(8)
        }
        .frame(height: min(220, CGFloat(proposal.targets.count) * 20 + 14))
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
      }
    }
  }

  private func summary(_ proposal: CleanupProposal) -> String {
    guard proposal.canProceed else { return "Nothing is left to end." }
    let count = proposal.targets.count
    return "\(count) \(count == 1 ? "process" : "processes") using "
      + Format.memory(proposal.residentBytes)
  }

  @ViewBuilder
  private func leftAlone(_ proposal: CleanupProposal) -> some View {
    if !proposal.refused.isEmpty {
      VStack(alignment: .leading, spacing: 2) {
        Text("Left alone")
          .font(.subheadline.weight(.semibold))
        ForEach(proposal.refused.prefix(4), id: \.process) { refusal in
          Text(verbatim: "\(refusal.process.pid): \(refusal.reason.explanation)")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        if proposal.refused.count > 4 {
          Text(verbatim: "and \(proposal.refused.count - 4) more")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  @ViewBuilder
  private func resume(_ proposal: CleanupProposal) -> some View {
    if !proposal.resume.isEmpty {
      VStack(alignment: .leading, spacing: 4) {
        Text(proposal.resume.count == 1 ? "To reopen it later" : "To reopen them later")
          .font(.subheadline.weight(.semibold))
        ScrollView {
          VStack(alignment: .leading, spacing: 4) {
            ForEach(proposal.resume) { resume in
              HStack {
                Text(verbatim: resume.command)
                  .font(.system(.callout, design: .monospaced))
                  .lineLimit(1)
                  .truncationMode(.middle)
                  .textSelection(.enabled)
                  .help(resume.title)
                Spacer()
                Button("Copy") { Pasteboard.copy(resume.command) }
                  .accessibilityLabel("Copy Resume Command")
                  .accessibilityIdentifier("cleanup.copy-resume")
              }
            }
          }
        }
        .frame(height: min(112, CGFloat(proposal.resume.count) * 28))
      }
    }
  }

  @ViewBuilder
  private func footer(_ flow: CleanupFlow) -> some View {
    switch flow.stage {
    case .proposed:
      HStack {
        Text(explanation(flow.proposal))
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Spacer()
        Button("Cancel", role: .cancel) { model.cleanup = nil }
          .keyboardShortcut(.cancelAction)
          .accessibilityIdentifier("cleanup.cancel")
        // No default-action shortcut: a Cleanup is confirmed by a deliberate click.
        Button(confirmation(flow.proposal), role: .destructive) {
          Task { await model.carryOutCleanup() }
        }
        .disabled(!flow.proposal.canProceed)
        .accessibilityIdentifier("cleanup.confirm")
      }
    case .running:
      HStack(spacing: 8) {
        ProgressView()
          .controlSize(.small)
        Text(flow.proposal.means == .endProcesses ? "Ending…" : "Shutting down…")
          .foregroundStyle(.secondary)
        Spacer()
      }
    case .finished(let report):
      HStack {
        Text(verbatim: report.text)
        Spacer()
        Button("Done") { model.cleanup = nil }
          .keyboardShortcut(.defaultAction)
          .accessibilityIdentifier("cleanup.done")
      }
    }
  }

  private func explanation(_ proposal: CleanupProposal) -> String {
    switch proposal.means {
    case .endProcesses:
      let seconds = model.terminator.grace.components.seconds
      return "Each process is asked to exit. What has not exited after \(seconds) seconds "
        + "is ended by force."
    case .shutDownSimulator:
      return "Uses Xcode's own tool."
    }
  }

  private func confirmation(_ proposal: CleanupProposal) -> String {
    switch proposal.means {
    case .endProcesses:
      let count = proposal.targets.count
      return count == 1 ? "End 1 Process" : "End \(count) Processes"
    case .shutDownSimulator:
      return "Shut Down"
    }
  }
}

private struct TargetRow: View {
  let target: CleanupProposal.Target

  var body: some View {
    HStack(spacing: 10) {
      Text(verbatim: String(target.process.pid))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .frame(width: 56, alignment: .trailing)
      Text(verbatim: target.name)
        .lineLimit(1)
      Spacer()
      Text(verbatim: place)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      Text(Format.memory(target.process.residentBytes))
        .monospacedDigit()
        .frame(width: 76, alignment: .trailing)
    }
    .font(.callout)
  }

  /// What the process is and which Session it belongs to, as far as that is known.
  private var place: String {
    [target.kind?.label, target.session?.displayTitle]
      .compactMap(\.self)
      .joined(separator: " · ")
  }
}

extension CleanupReport {
  /// What a Cleanup did, in a sentence.
  var text: String {
    switch self {
    case .processes(let outcome): outcome.text
    case .simulator(true): "The simulator was shut down."
    case .simulator(false): "The simulator could not be shut down."
    }
  }
}

/// The system clipboard.
enum Pasteboard {
  static func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }
}
