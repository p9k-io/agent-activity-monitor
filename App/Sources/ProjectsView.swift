import AAMCore
import SwiftUI

/// Projects, their Sessions and what runs for each.
struct ProjectsView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    let projects = model.sample?.observation.inventory.projects ?? []
    if projects.isEmpty {
      ContentUnavailableView(
        model.sample == nil ? "Looking…" : "No Sessions",
        systemImage: "folder",
        description: Text("Start Claude Code or Codex in a terminal and it shows up here."))
    } else {
      List {
        ForEach(projects) { project in
          Section {
            ForEach(project.sessions) { group in
              SessionRow(group: group)
            }
            if !project.loose.isEmpty {
              DisclosureGroup {
                ProcessRows(processes: project.loose)
              } label: {
                LooseLabel(processes: project.loose)
              }
            }
          } header: {
            HStack {
              Text(project.project.name)
                .font(.headline)
              Text(project.project.root)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
            }
          }
        }
      }
    }
  }
}

private struct SessionRow: View {
  @Environment(AppModel.self) private var model
  let group: SessionInventory

  var body: some View {
    DisclosureGroup {
      ProcessRows(processes: group.processes)
    } label: {
      HStack(spacing: 10) {
        VStack(alignment: .leading, spacing: 1) {
          Text(group.session.displayTitle)
            .lineLimit(1)
          Text(
            "\(group.session.id.harness.label) · last active \(group.session.lastActive(now: model.now))"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        Spacer()
        StateBadge(state: group.session.state)
        Text(Format.cpu(model.cpu(of: group.processes)))
          .monospacedDigit()
          .frame(width: 70, alignment: .trailing)
        Text(Format.memory(group.residentBytes))
          .monospacedDigit()
          .frame(width: 80, alignment: .trailing)
        Text("\(group.processes.count)")
          .monospacedDigit()
          .foregroundStyle(.secondary)
          .frame(width: 36, alignment: .trailing)
        Button("End…") { model.propose { $0.ending(group.session.id) } }
          .buttonStyle(.link)
          .help("End this Session and everything it started")
          .accessibilityLabel("End Session")
          .accessibilityIdentifier("session.end")
      }
      .contextMenu {
        Button("End Session…") { model.propose { $0.ending(group.session.id) } }
        if let command = group.session.resumeCommand {
          Button("Copy Resume Command") { Pasteboard.copy(command) }
        }
      }
    }
  }
}

private struct LooseLabel: View {
  let processes: [AttributedProcess]

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 1) {
        Text("Not tied to one Session")
        Text(
          processes.contains(where: \.isOrphan)
            ? "Left behind by Sessions that ended, or running inside the Project"
            : "Running inside the Project"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      Spacer()
      Text(Format.memory(processes.reduce(0) { $0 + $1.process.residentBytes }))
        .monospacedDigit()
        .frame(width: 80, alignment: .trailing)
      Text("\(processes.count)")
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .frame(width: 36, alignment: .trailing)
    }
  }
}

/// One line per process: identifier, name, kind, Evidence, CPU and memory.
private struct ProcessRows: View {
  @Environment(AppModel.self) private var model
  let processes: [AttributedProcess]

  var body: some View {
    ForEach(processes) { attributed in
      HStack(spacing: 10) {
        Text(String(attributed.process.pid))
          .monospacedDigit()
          .foregroundStyle(.secondary)
          .frame(width: 60, alignment: .trailing)
        Text(
          attributed.process.isZombie
            ? "\(attributed.process.name) (zombie)" : attributed.process.name
        )
        .lineLimit(1)
        Spacer()
        if attributed.isOrphan {
          Text("Orphan")
            .font(.caption)
            .foregroundStyle(.orange)
        }
        Text(attributed.kind.label)
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(width: 110, alignment: .leading)
        Text(attributed.evidence.label)
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(width: 90, alignment: .leading)
        Text(Format.cpu(model.cpu(of: attributed.process)))
          .monospacedDigit()
          .frame(width: 70, alignment: .trailing)
        Text(Format.memory(attributed.process.residentBytes))
          .monospacedDigit()
          .frame(width: 80, alignment: .trailing)
      }
      .font(.callout)
    }
  }
}
