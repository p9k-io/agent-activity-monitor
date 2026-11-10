import AAMCore
import SwiftUI

@main
struct AgentActivityMonitorApp: App {
  var body: some Scene {
    MenuBarExtra("Agent Activity Monitor", systemImage: "gauge.with.dots.needle.33percent") {
      Text("Agent Activity Monitor \(AAM.version)")
      Divider()
      Button("Quit") {
        NSApplication.shared.terminate(nil)
      }
      .keyboardShortcut("q")
    }
  }
}
