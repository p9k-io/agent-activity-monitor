import AAMCore
import SwiftUI

/// How often the app was opened again while it already ran.
@MainActor
@Observable
final class Reopening {
  static let shared = Reopening()
  var count = 0
}

/// Hears that the app was opened again while it already ran.
///
/// When the menu bar has no room left, macOS hides the gauge, and opening the app again is then
/// the only way to its window.
final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
    Reopening.shared.count += 1
    return false
  }
}

@main
struct AgentActivityMonitorApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  @Environment(\.openWindow) private var openWindow
  @State private var model = AppModel()

  /// The window opens by itself the first time the app runs, whenever it is started with
  /// `-showWindow YES`, and when the app is opened again while it runs. Otherwise the app lives
  /// in the menu bar.
  private let opensWindowAtLaunch: Bool = {
    let defaults = UserDefaults.standard
    let firstLaunch = !defaults.bool(forKey: "hasLaunchedBefore")
    defaults.set(true, forKey: "hasLaunchedBefore")
    return firstLaunch || defaults.bool(forKey: "showWindow")
  }()

  var body: some Scene {
    MenuBarExtra {
      MenuPanel()
        .environment(model)
    } label: {
      Image(systemName: model.gaugeSymbol)
        .accessibilityLabel("Agent Activity Monitor")
      // Cleanup requests that wait for a decision are counted next to the gauge.
      if !model.pendingRequests.isEmpty {
        Text("\(model.pendingRequests.count)")
      }
    }
    .menuBarExtraStyle(.window)

    Window("Agent Activity Monitor", id: "main") {
      MainWindow()
        .environment(model)
    }
    .defaultSize(width: 980, height: 640)
    .defaultLaunchBehavior(opensWindowAtLaunch ? .presented : .suppressed)
    .onChange(of: Reopening.shared.count) {
      openWindow(id: "main")
      NSApp.activate()
    }

    Settings {
      SettingsView()
        .environment(model)
    }

    #if DEBUG
      // The menu bar panel in an ordinary window, so that it can be looked at and captured
      // without clicking the menu bar: start the app with `-showPanel YES`.
      Window("Menu Bar Panel", id: "panel-preview") {
        MenuPanel()
          .environment(model)
      }
      .windowResizability(.contentSize)
      .defaultLaunchBehavior(
        UserDefaults.standard.bool(forKey: "showPanel") ? .presented : .suppressed)
    #endif
  }
}
