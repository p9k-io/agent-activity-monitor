import AAMCore
import SwiftUI

/// What is no longer needed, by kind, with the reason for each finding.
struct StaleView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    if model.findings.isEmpty {
      ContentUnavailableView(
        model.sample == nil ? "Looking…" : "Nothing stale",
        systemImage: "leaf",
        description: Text("Idle Sessions, leftovers and forgotten load show up here."))
    } else {
      List {
        ForEach(StaleFinding.Kind.allCases, id: \.self) { kind in
          let findings = model.findings.filter { $0.kind == kind }
          if !findings.isEmpty {
            Section(kind.heading) {
              ForEach(findings) { finding in
                FindingRow(finding: finding, now: model.now)
              }
            }
          }
        }
      }
      .safeAreaInset(edge: .bottom) {
        HStack {
          Text(
            "A Cleanup of everything here would free \(Format.memory(model.reclaimableBytes))."
          )
          .font(.callout)
          .foregroundStyle(.secondary)
          Spacer()
          Button("Clean Up All…") { model.propose { $0.cleaningUp(model.findings) } }
            .disabled(!model.findings.contains(where: \.canCleanUp))
            .accessibilityIdentifier("stale.clean-up-all")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
      }
    }
  }
}

private struct FindingRow: View {
  @Environment(AppModel.self) private var model
  let finding: StaleFinding
  let now: Date

  var body: some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 1) {
        Text(finding.title)
          .lineLimit(1)
        Text("\(finding.project.name) · \(finding.reason.text(now: now))")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer()
      if !finding.canCleanUp {
        Text("Cannot be cleaned up")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Text(Format.memory(finding.residentBytes))
        .monospacedDigit()
        .frame(width: 80, alignment: .trailing)
      Text("\(finding.processes.count)")
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .frame(width: 36, alignment: .trailing)
      Button("Clean Up…") { model.propose { $0.cleaningUp([finding]) } }
        .buttonStyle(.link)
        .disabled(!finding.canCleanUp)
        .opacity(finding.canCleanUp ? 1 : 0)
        .accessibilityIdentifier("stale.clean-up")
    }
  }
}
