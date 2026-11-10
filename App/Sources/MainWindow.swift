import AAMCore
import SwiftUI

struct MainWindow: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var model = model
    NavigationSplitView {
      List(MainSection.allCases, selection: $model.section) { section in
        Label(section.rawValue, systemImage: section.symbol)
          .badge(badge(of: section))
          .tag(section)
      }
      .navigationSplitViewColumnWidth(min: 160, ideal: 180)
    } detail: {
      Group {
        switch model.section {
        case .overview: OverviewView()
        case .projects: ProjectsView()
        case .stale: StaleView()
        case .requests: RequestsView()
        case .reports: ReportsView()
        }
      }
      .navigationTitle(model.section.rawValue)
    }
    .sheet(item: $model.cleanup) { _ in
      CleanupSheet()
    }
    .onAppear { model.watch() }
    .onDisappear { model.unwatch() }
  }

  private func badge(of section: MainSection) -> Int {
    switch section {
    case .stale: model.findings.count
    case .requests: model.pendingRequests.count
    case .overview, .projects, .reports: 0
    }
  }
}

/// The summary and the Culprits.
struct OverviewView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      summary
      Text("Using CPU now")
        .font(.headline)
      if model.culprits.isEmpty {
        ContentUnavailableView(
          model.sample == nil ? "Measuring…" : "Nothing is working hard",
          systemImage: "gauge.with.dots.needle.0percent",
          description: Text("Whatever uses more than a quarter of one core shows up here."))
      } else {
        Table(model.culprits) {
          TableColumn("What") { tracked in
            VStack(alignment: .leading, spacing: 1) {
              Text(tracked.culprit.title)
              Text(tracked.culprit.owner.label)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
          TableColumn("CPU") { Text(Format.cpu($0.culprit.cpuPercent)).monospacedDigit() }
            .width(80)
          TableColumn("Memory") { Text(Format.memory($0.culprit.residentBytes)).monospacedDigit() }
            .width(90)
          TableColumn("Processes") { Text("\($0.culprit.processes.count)").monospacedDigit() }
            .width(80)
          TableColumn("For") { Text(Format.span(from: $0.hotSince, to: model.now)) }
            .width(80)
          TableColumn("") { tracked in
            // Only what can be cleaned up gets a command. The rest is shown, nothing more.
            if let command = tracked.culprit.cleanupCommand {
              Button(command) { model.propose { $0.ending(tracked.culprit) } }
                .buttonStyle(.link)
                .accessibilityIdentifier("culprit.clean-up")
            }
          }
          .width(110)
        }
      }
    }
    .padding(16)
  }

  private var summary: some View {
    let sessions = model.sessions
    let working = sessions.count { $0.session.state == .working }
    let waiting = sessions.count { $0.session.state == .waiting }
    let memory = sessions.reduce(UInt64(0)) { $0 + $1.residentBytes }
    let processes = sessions.reduce(0) { $0 + $1.processes.count }
    return HStack(spacing: 12) {
      Tile(
        title: "Sessions", value: "\(sessions.count)",
        detail: "\(working) working · \(waiting) waiting for you")
      Tile(
        title: "In Sessions", value: Format.memory(memory),
        detail: "\(processes) processes")
      Tile(
        title: "Culprits", value: Format.cpu(model.culpritCPU),
        detail:
          "\(model.culprits.count) using CPU · machine is \(model.thermalState.label.lowercased())"
      )
      Tile(
        title: "Could be freed", value: Format.memory(model.reclaimableBytes),
        detail: "\(model.findings.count) stale")
    }
  }
}
