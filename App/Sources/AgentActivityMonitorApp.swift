import AAMCore
import SwiftUI

@main
struct AgentActivityMonitorApp: App {
  @State private var model = AppModel()

  /// The window opens by itself the first time the app runs, and whenever it is started with
  /// `-showWindow YES`. Otherwise the app lives in the menu bar.
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
    }
    .menuBarExtraStyle(.window)

    Window("Agent Activity Monitor", id: "main") {
      MainWindow()
        .environment(model)
    }
    .defaultSize(width: 980, height: 640)
    .defaultLaunchBehavior(opensWindowAtLaunch ? .presented : .suppressed)

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
