import AAMCore
import SwiftUI

/// Where CPU time went over the last days, per Project and Session.
struct ReportsView: View {
  @Environment(AppModel.self) private var model
  @State private var days = 7
  @State private var report: UsageReport?
  @State private var loaded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Picker("Period", selection: $days) {
          Text("24 hours").tag(1)
          Text("7 days").tag(7)
          Text("30 days").tag(30)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 280)
        Spacer()
        if let report, !report.rows.isEmpty {
          Text("\(Format.cpuTime(report.cpuSeconds)) of CPU time")
            .foregroundStyle(.secondary)
        }
      }
      content
    }
    .padding(16)
    .task(id: days) {
      // Read again every minute while the section is on show: that is how often it changes.
      while !Task.isCancelled {
        report = await model.usageReport(days: days)
        loaded = true
        try? await Task.sleep(for: .seconds(60))
      }
    }
  }

  @ViewBuilder private var content: some View {
    if let report, !report.rows.isEmpty {
      let heaviest = report.rows.map(\.cpuSeconds).max() ?? 1
      List {
        ForEach(report.projects) { project in
          Section {
            ForEach(report.rows.filter { $0.project == project.project }) { row in
              ReportRow(row: row, heaviest: heaviest)
            }
          } header: {
            HStack {
              Text(verbatim: project.project.name)
                .font(.headline)
              Spacer()
              Text(Format.cpuTime(project.cpuSeconds))
                .monospacedDigit()
            }
          }
        }
      }
    } else {
      ContentUnavailableView(
        loaded ? "Nothing recorded yet" : "Reading…",
        systemImage: "chart.bar",
        description: Text(
          "History is kept while the app is running. "
            + "What uses less than 1 % of one core is not counted."))
    }
  }
}

private struct ReportRow: View {
  let row: UsageReport.Row
  let heaviest: Double

  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: row.title)
          .lineLimit(1)
        Text(verbatim: detail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer()
      ProgressView(value: row.cpuSeconds, total: max(heaviest, 1))
        .frame(width: 160)
        .accessibilityHidden(true)
      Text(Format.cpuTime(row.cpuSeconds))
        .monospacedDigit()
        .frame(width: 80, alignment: .trailing)
      Text(row.peakResidentBytes > 0 ? Format.memory(row.peakResidentBytes) : "–")
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .frame(width: 90, alignment: .trailing)
    }
  }

  /// What the CPU time went on, the two largest shares.
  private var detail: String {
    row.byKind.prefix(2)
      .map { "\($0.kind.label) \(Format.cpuTime($0.cpuSeconds))" }
      .joined(separator: " · ")
  }
}
