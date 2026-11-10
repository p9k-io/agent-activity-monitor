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

  private static let key = "settings"

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
