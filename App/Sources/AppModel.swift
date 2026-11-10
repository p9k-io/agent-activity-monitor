import AAMCleanup
import AAMCore
import AAMPlatform
import Foundation
import Observation

/// The parts of the main window.
enum MainSection: String, CaseIterable, Identifiable {
  case overview = "Overview"
  case projects = "Projects"
  case stale = "Stale"
  case requests = "Requests"
  case reports = "Reports"

  var id: Self { self }

  var symbol: String {
    switch self {
    case .overview: "gauge.with.dots.needle.50percent"
    case .projects: "folder"
    case .stale: "leaf"
    case .requests: "tray"
    case .reports: "chart.bar"
    }
  }
}

/// What the app shows: the latest sample, kept fresh by the Sampler.
@Observable
final class AppModel {
  private(set) var sample: Sample?
  private(set) var thermalState = ProcessInfo.processInfo.thermalState
  /// Cleanup requests, the oldest first.
  private(set) var requests: [CleanupRequest] = []
  /// Words a Cleanup of what the latest sample shows.
  private(set) var proposer: CleanupProposer?
  /// The Cleanup a person is looking at: proposed, being carried out or finished.
  var cleanup: CleanupFlow?
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

  /// True when the app shows made-up data instead of this machine: `-demo YES`, debug builds
  /// only. Nothing is read from the machine or the store then.
  let isDemo: Bool
  /// Shared with the Sampler. Cleanup requests are read from it and decided in it.
  let store: Store?
  /// The only thing in the app that ends processes, and only after a person confirmed.
  let terminator = Terminator(source: SystemProcessSource(markerNames: []))

  /// Decides when load that does not stop is worth a notification.
  private var alerts = LoadAlerts(after: .seconds(900))
  /// How many views are showing live data right now.
  private var watchers = 0
  private let sampler: Sampler
  private var loop: Task<Void, Never>?

  /// Looking often costs CPU, so the app looks often only while someone is watching.
  private var interval: Duration {
    watchers > 0 ? .seconds(3) : .seconds(10)
  }

  init() {
    #if DEBUG
      isDemo = UserDefaults.standard.bool(forKey: "demo")
    #else
      isDemo = false
    #endif
    let store = isDemo ? nil : try? Store(url: Store.defaultURL)
    self.store = store
    let sampler = Sampler.system(store: store)
    self.sampler = sampler
    #if DEBUG
      if isDemo {
        let sample = DemoData.sample()
        show(sample)
        requests = DemoData.requests(for: sample)
        return
      }
    #endif
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
  func run() {
    guard !isDemo else { return }
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
    show(sample)
    thermalState = ProcessInfo.processInfo.thermalState
    if let store {
      requests = (try? store.requests()) ?? []
    }
    alert(about: sample)
  }

  /// Tells about load that has gone on for too long, when the person asked to be told.
  private func alert(about sample: Sample) {
    alerts.after = .seconds(settings.alertAfterMinutes * 60)
    alerts.above = settings.alertAboveCPU
    // Asked on every look, so that a stretch that began while alerts were off is not told
    // about the moment they are switched on.
    let due = alerts.due(sample.culprits, now: sample.takenAt)
    guard settings.alertsEnabled else { return }
    for tracked in due {
      Notifier.post(LoadAlerts.text(for: tracked, now: sample.takenAt), id: tracked.id)
    }
  }

  private func show(_ sample: Sample) {
    self.sample = sample
    proposer = CleanupProposer(reading: sample.observation, planner: terminator.planner)
  }

  /// Records what was decided about a Cleanup request, in the store and in what is on show.
  func record(_ decided: CleanupRequest) {
    try? store?.update(decided)
    if let index = requests.firstIndex(where: { $0.id == decided.id }) {
      requests[index] = decided
    }
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
