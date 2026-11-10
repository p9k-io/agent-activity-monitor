import AAMCore
import SwiftUI

/// The panel under the menu bar icon: what is using CPU now, and what could go.
struct MenuPanel: View {
  @Environment(AppModel.self) private var model
  @Environment(\.openWindow) private var openWindow
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      Divider()
      culprits
      Divider()
      stale
      if !model.pendingRequests.isEmpty {
        Divider()
        requests
      }
      Divider()
      footer
    }
    .padding(14)
    .frame(width: 380)
    .onAppear { model.watch() }
    .onDisappear { model.unwatch() }
  }

  private var header: some View {
    HStack {
      Text("Agent Activity Monitor")
        .font(.headline)
      Spacer()
      Label(model.thermalState.label, systemImage: "thermometer.medium")
        .font(.caption)
        .foregroundStyle(model.thermalState == .nominal ? Color.secondary : Color.orange)
    }
  }

  private var culprits: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Using CPU now")
        .font(.subheadline.weight(.semibold))
      if model.sample == nil {
        Text("Measuring…")
          .foregroundStyle(.secondary)
      } else if model.culprits.isEmpty {
        Text("Nothing is working hard.")
          .foregroundStyle(.secondary)
      } else {
        ForEach(model.culprits.prefix(5)) { tracked in
          HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
              Text(tracked.culprit.title)
                .lineLimit(1)
              Text(
                "\(tracked.culprit.owner.label) · for \(Format.span(from: tracked.hotSince, to: model.now))"
              )
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
            }
            Spacer()
            Text(Format.cpu(tracked.culprit.cpuPercent))
              .monospacedDigit()
          }
        }
      }
    }
  }

  private var stale: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("No longer needed")
        .font(.subheadline.weight(.semibold))
      if model.findings.isEmpty {
        Text("Nothing stale.")
          .foregroundStyle(.secondary)
      } else {
        ForEach(StaleFinding.Kind.allCases, id: \.self) { kind in
          let count = model.findings.count { $0.kind == kind }
          if count > 0 {
            HStack {
              Text(kind.heading)
              Spacer()
              Text("\(count)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
          }
        }
        HStack {
          Text("\(Format.memory(model.reclaimableBytes)) could be freed")
            .font(.caption)
            .foregroundStyle(.secondary)
          Spacer()
          Button("Review…") { show(.stale) }
        }
      }
    }
  }

  private var requests: some View {
    let count = model.pendingRequests.count
    return HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text("Cleanup requests")
          .font(.subheadline.weight(.semibold))
        Text("\(count) waiting for your decision")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button("Decide…") { show(.requests) }
    }
  }

  private var footer: some View {
    HStack {
      Button("Open Window") { show(.overview) }
      Spacer()
      Button("Settings…") {
        openSettings()
        NSApp.activate()
      }
      Button("Quit") { NSApp.terminate(nil) }
    }
  }

  private func show(_ section: MainSection) {
    model.section = section
    openWindow(id: "main")
    NSApp.activate()
  }
}
