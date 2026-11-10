import AAMCore
import AAMPlatform
import Foundation
import Observation

/// The parts of the main window.
enum MainSection: String, CaseIterable, Identifiable {
  case overview = "Overview"
  case projects = "Projects"
  case stale = "Stale"

  var id: Self { self }

  var symbol: String {
    switch self {
    case .overview: "gauge.with.dots.needle.50percent"
    case .projects: "folder"
    case .stale: "leaf"
    }
  }
}

/// What the app shows: the latest sample, kept fresh by the Sampler.
@Observable
final class AppModel {
  private(set) var sample: Sample?
  private(set) var thermalState = ProcessInfo.processInfo.thermalState
  /// The section the window shows. `-section stale` on the command line chooses where it opens.
  var section =
    UserDefaults.standard.string(forKey: "section")
    .flatMap { name in MainSection.allCases.first { $0.rawValue.lowercased() == name.lowercased() }
    }
    ?? .overview
  var settings = AppSettings.load() {
    didSet {
      guard settings != oldValue else { return }
      settings.save()
      let samplerSettings = settings.samplerSettings
      Task { await sampler.update(samplerSettings) }
    }
  }

  /// How many views are showing live data right now.
  private var watchers = 0
  private let sampler: Sampler
  private var loop: Task<Void, Never>?

  /// Looking often costs CPU, so the app looks often only while someone is watching.
  private var interval: Duration {
    watchers > 0 ? .seconds(3) : .seconds(10)
  }

  init(sampler: Sampler = .system()) {
    self.sampler = sampler
    let samplerSettings = settings.samplerSettings
    Task {
      await sampler.update(samplerSettings)
      // Two looks close together, so that there is CPU use to show from the start.
      await look()
      try? await Task.sleep(for: .seconds(1))
      run()
    }
  }

  /// Call when a view with live data appears.
  func watch() {
    watchers += 1
    if watchers == 1 { run() }
  }

  /// Call when a view with live data disappears.
  func unwatch() {
    watchers = max(0, watchers - 1)
  }

  /// Starts the loop over, with a look right away.
  private func run() {
    loop?.cancel()
    loop = Task {
      while !Task.isCancelled {
        await look()
        try? await Task.sleep(for: interval)
      }
    }
  }

  private func look() async {
    let sample = await sampler.tick()
    guard !Task.isCancelled else { return }
    self.sample = sample
    thermalState = ProcessInfo.processInfo.thermalState
  }

  // MARK: What the views read

  var now: Date { sample?.takenAt ?? Date() }

  var sessions: [SessionInventory] {
    sample?.observation.inventory.projects.flatMap(\.sessions) ?? []
  }

  var culprits: [TrackedCulprit] { sample?.culprits ?? [] }

  var findings: [StaleFinding] { sample?.findings ?? [] }

  var reclaimableBytes: UInt64 {
    findings.filter(\.canCleanUp).reduce(0) { $0 + $1.residentBytes }
  }

  var culpritCPU: Double {
    culprits.reduce(0) { $0 + $1.culprit.cpuPercent }
  }

  func cpu(of processes: [AttributedProcess]) -> Double {
    guard let usage = sample?.usage else { return 0 }
    return processes.reduce(0) { $0 + usage.cpuPercent(of: $1.process.key) }
  }

  func cpu(of process: ProcessRecord) -> Double {
    sample?.usage.cpuPercent(of: process.key) ?? 0
  }

  /// A symbol for the menu bar that fills up as Culprits use more of the machine.
  var gaugeSymbol: String {
    let share = culpritCPU / Double(ProcessInfo.processInfo.activeProcessorCount * 100)
    return switch share {
    case ..<0.1: "gauge.with.dots.needle.0percent"
    case ..<0.3: "gauge.with.dots.needle.33percent"
    case ..<0.55: "gauge.with.dots.needle.50percent"
    case ..<0.8: "gauge.with.dots.needle.67percent"
    default: "gauge.with.dots.needle.100percent"
    }
  }
}

extension ProcessInfo.ThermalState {
  var label: String {
    switch self {
    case .nominal: "Cool"
    case .fair: "Warm"
    case .serious: "Hot"
    case .critical: "Very hot"
    @unknown default: "Unknown"
    }
  }
}
