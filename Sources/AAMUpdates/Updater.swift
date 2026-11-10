import Sparkle

/// Looks for a newer version of the app and installs it when a person agrees.
///
/// Checking for updates is the only reason the app ever uses the network. Sparkle asks before
/// it starts checking by itself, and every update must carry a signature made with the key
/// whose public half is in the app. Only the app links this module.
@MainActor
public final class Updater {
  private let controller: SPUStandardUpdaterController?

  /// - Parameter enabled: False in debug builds, which have no version to compare.
  public init(enabled: Bool) {
    controller =
      enabled
      ? SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
      : nil
  }

  public var isEnabled: Bool { controller != nil }

  public func checkForUpdates() {
    controller?.checkForUpdates(nil)
  }
}
