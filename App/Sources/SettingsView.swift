import AAMCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
  @Environment(AppModel.self) private var model
  @State private var launchesAtLogin = SMAppService.mainApp.status == .enabled
  @State private var loginItemProblem: String?
  @State private var alertProblem: String?

  var body: some View {
    @Bindable var model = model
    Form {
      Section("General") {
        Toggle("Open at login", isOn: $launchesAtLogin)
          .onChange(of: launchesAtLogin) { _, wanted in
            setLaunchAtLogin(wanted)
          }
        if let loginItemProblem {
          Text(loginItemProblem)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Section("When something counts as Stale") {
        hours("A Session without activity for", value: $model.settings.idleSessionHours)
        hours("A dev server without CPU use for", value: $model.settings.idleDevServerHours)
        hours(
          "Induced load after nothing worked in its Project for",
          value: $model.settings.quietProjectHours)
        LabeledContent("A leftover after its Session ended") {
          Stepper(
            "\(Int(model.settings.orphanMinutes)) min", value: $model.settings.orphanMinutes,
            in: 1...60)
        }
      }

      Section("Culprits") {
        LabeledContent("Listed from") {
          Stepper(
            "\(Int(model.settings.culpritThreshold)) % of one core",
            value: $model.settings.culpritThreshold, in: 5...200, step: 5)
        }
      }

      Section("Alerts") {
        Toggle("Tell me when something keeps using CPU", isOn: $model.settings.alertsEnabled)
          .onChange(of: model.settings.alertsEnabled) { _, wanted in
            guard wanted else { return }
            Task {
              // Without permission there is nothing to switch on.
              if await !Notifier.askPermission() {
                model.settings.alertsEnabled = false
                alertProblem = "Notifications are not allowed for this app in System Settings."
              } else {
                alertProblem = nil
              }
            }
          }
        if let alertProblem {
          Text(alertProblem)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        LabeledContent("After") {
          Stepper(
            "\(Int(model.settings.alertAfterMinutes)) min",
            value: $model.settings.alertAfterMinutes, in: 5...120, step: 5)
        }
        LabeledContent("From") {
          Stepper(
            "\(Int(model.settings.alertAboveCPU)) % of one core",
            value: $model.settings.alertAboveCPU, in: 25...800, step: 25)
        }
      }

      Section {
        LabeledContent("Version", value: AAM.version)
      }
    }
    .formStyle(.grouped)
    .frame(width: 520)
  }

  private func hours(_ title: String, value: Binding<Double>) -> some View {
    LabeledContent(title) {
      Stepper("\(Int(value.wrappedValue)) h", value: value, in: 1...168)
    }
  }

  private func setLaunchAtLogin(_ wanted: Bool) {
    do {
      if wanted {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      loginItemProblem = nil
    } catch {
      loginItemProblem = "Could not change the login item: \(error.localizedDescription)"
      launchesAtLogin = SMAppService.mainApp.status == .enabled
    }
  }
}
