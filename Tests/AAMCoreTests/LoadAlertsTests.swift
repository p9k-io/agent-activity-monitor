import AAMCore
import Foundation
import Testing

struct LoadAlertsTests {
  func culprit(_ id: String, hotFor seconds: TimeInterval, cpu: Double = 150) -> TrackedCulprit {
    TrackedCulprit(
      culprit: Culprit(
        id: id, title: id, owner: .none, cpuPercent: cpu, residentBytes: 0, processes: []),
      hotSince: epoch.addingTimeInterval(-seconds))
  }

  @Test func `a Culprit is told about once it has been one for long enough`() {
    var alerts = LoadAlerts(after: .seconds(600))

    #expect(alerts.due([culprit("sim", hotFor: 599)], now: epoch).isEmpty)
    #expect(alerts.due([culprit("sim", hotFor: 600)], now: epoch).map(\.id) == ["sim"])
  }

  @Test func `the same stretch of load is told about once`() {
    var alerts = LoadAlerts(after: .seconds(600))

    _ = alerts.due([culprit("sim", hotFor: 700)], now: epoch)

    #expect(alerts.due([culprit("sim", hotFor: 900)], now: epoch).isEmpty)
  }

  @Test func `a Culprit that cooled down and heated up again is told about again`() {
    var alerts = LoadAlerts(after: .seconds(600))
    _ = alerts.due([culprit("sim", hotFor: 700)], now: epoch)
    _ = alerts.due([], now: epoch)

    #expect(alerts.due([culprit("sim", hotFor: 650)], now: epoch).map(\.id) == ["sim"])
  }

  @Test func `only load above the given CPU use counts`() {
    var alerts = LoadAlerts(after: .seconds(600), above: 100)

    let due = alerts.due(
      [culprit("light", hotFor: 900, cpu: 60), culprit("heavy", hotFor: 900, cpu: 240)],
      now: epoch)

    #expect(due.map(\.id) == ["heavy"])
  }

  @Test func `an alert says what it is about, how much and for how long`() {
    let alert = culprit("iOS Simulator", hotFor: 5400, cpu: 310.5)

    #expect(
      LoadAlerts.text(for: alert, now: epoch, locale: Locale(identifier: "en_US"))
        == "iOS Simulator has been using 310.5 % CPU for 1h 30m.")
  }
}
