import AAMCore
import AAMPlatform
import Foundation

/// What a person can adjust. Kept in the app's preferences.
struct AppSettings: Codable, Equatable {
  var idleSessionHours = 24.0
  var idleDevServerHours = 2.0
  var quietProjectHours = 2.0
  var orphanMinutes = 2.0
  /// CPU use, in percent of one core, from which something is listed as a Culprit.
  var culpritThreshold = 25.0
  /// Whether a notification is sent about load that does not stop. Off unless asked for.
  var alertsEnabled = false
  /// How long something must have been using CPU before a notification is sent.
  var alertAfterMinutes = 15.0
  /// CPU use, in percent of one core, from which load is worth a notification.
  var alertAboveCPU = 100.0

  private static let key = "settings"

  init() {}

  /// Settings saved by an earlier version lack what was added since. What is missing keeps
  /// its default instead of throwing the saved settings away.
  init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    func value<T: Decodable>(_ key: CodingKeys, or fallback: T) -> T {
      (try? values.decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
    idleSessionHours = value(.idleSessionHours, or: idleSessionHours)
    idleDevServerHours = value(.idleDevServerHours, or: idleDevServerHours)
    quietProjectHours = value(.quietProjectHours, or: quietProjectHours)
    orphanMinutes = value(.orphanMinutes, or: orphanMinutes)
    culpritThreshold = value(.culpritThreshold, or: culpritThreshold)
    alertsEnabled = value(.alertsEnabled, or: alertsEnabled)
    alertAfterMinutes = value(.alertAfterMinutes, or: alertAfterMinutes)
    alertAboveCPU = value(.alertAboveCPU, or: alertAboveCPU)
  }

  static func load(from defaults: UserDefaults = .standard) -> AppSettings {
    guard let data = defaults.data(forKey: key),
      let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
    else { return AppSettings() }
    return settings
  }

  func save(to defaults: UserDefaults = .standard) {
    if let data = try? JSONEncoder().encode(self) {
      defaults.set(data, forKey: Self.key)
    }
  }

  var samplerSettings: Sampler.Settings {
    Sampler.Settings(
      thresholds: StaleThresholds(
        idleSession: .seconds(idleSessionHours * 3600),
        idleDevServer: .seconds(idleDevServerHours * 3600),
        orphan: .seconds(orphanMinutes * 60),
        quietProject: .seconds(quietProjectHours * 3600)),
      culpritThreshold: culpritThreshold)
  }
}
