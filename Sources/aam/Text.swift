import AAMCore
import Foundation

// Human-readable output. The JSON output is the stable one; this may change freely.

/// Lays rows out in left-aligned columns, as wide as their widest cell.
func columns(_ header: [String], _ rows: [[String]]) -> String {
  let widths = header.indices.map { column in
    ([header] + rows).map { $0[column].count }.max() ?? 0
  }
  return ([header] + rows)
    .map { row in
      row.enumerated()
        .map { index, cell in
          index == row.count - 1
            ? cell : cell.padding(toLength: widths[index], withPad: " ", startingAt: 0)
        }
        .joined(separator: "  ")
    }
    .joined(separator: "\n")
}

func memory(_ bytes: UInt64) -> String {
  Format.memory(bytes)
}

/// How long ago `date` was, or a dash when it is not known.
func age(of date: Date?, now: Date) -> String {
  date.map { Format.span(from: $0, to: now) } ?? "-"
}

extension SessionsReport {
  func table(now: Date) -> String {
    columns(
      ["PROJECT", "HARNESS", "STATE", "LAST ACTIVE", "PROCS", "MEMORY", "TITLE"],
      sessions.map { row in
        [
          row.project, row.harness, row.state,
          row.state == "working" ? "now" : age(of: row.lastActivityAt, now: now),
          String(row.processCount), memory(row.residentBytes), row.title ?? "-",
        ]
      })
  }
}

extension ProcessesReport {
  var text: String {
    var lines: [String] = []
    for project in projects {
      lines.append("\(project.name)  \(project.root)")
      for detail in project.sessions {
        let session = detail.session
        lines.append("  \(session.harness)  \(session.state)  \(session.title ?? session.id)")
        let rows = detail.processes.map { process in
          [
            "    \(process.pid)", process.evidence ?? "-",
            process.isZombie ? "\(process.name) (zombie)" : process.name,
            memory(process.residentBytes),
          ]
        }
        lines.append(columns(["    PID", "EVIDENCE", "NAME", "MEMORY"], rows))
      }
    }
    if let unattributed {
      lines.append("unattributed")
      let rows = unattributed.map { ["    \($0.pid)", $0.name, memory($0.residentBytes)] }
      lines.append(columns(["    PID", "NAME", "MEMORY"], rows))
    } else {
      lines.append("\(unattributedCount) processes belong to no Session (--all lists them)")
    }
    return lines.joined(separator: "\n")
  }
}

extension CulpritsReport {
  var table: String {
    columns(
      ["CPU %", "MEMORY", "PROCS", "WHAT", "OWNER"],
      culprits.map { row in
        [
          String(format: "%.1f", row.cpuPercent), memory(row.residentBytes),
          String(row.pids.count), row.title, row.owner.label,
        ]
      })
  }
}

extension CulpritRow.Owner {
  var label: String {
    switch kind {
    case "session": "Session in \(project.map(lastComponent) ?? "-")"
    case "project": "Project \(project.map(lastComponent) ?? "-")"
    default: "-"
    }
  }

  private func lastComponent(_ path: String) -> String {
    path.split(separator: "/").last.map(String.init) ?? path
  }
}

extension MineReport {
  func text(now: Date) -> String {
    let header = [
      "Session  \(session.title ?? session.id)",
      "Project  \(session.project)  \(session.projectRoot)",
      "State    \(session.state), last active \(age(of: session.lastActivityAt, now: now)) ago",
      "Memory   \(memory(session.residentBytes)) in \(session.processCount) processes",
    ]
    let rows = processes.map { process in
      [
        String(process.pid), process.evidence ?? "-",
        process.isZombie ? "\(process.name) (zombie)" : process.name,
        memory(process.residentBytes),
      ]
    }
    return (header + ["", columns(["PID", "EVIDENCE", "NAME", "MEMORY"], rows)])
      .joined(separator: "\n")
  }
}

extension StaleReport {
  func text(now: Date) -> String {
    var lines = [
      columns(
        ["KIND", "WHAT", "PROJECT", "WHY", "PROCS", "MEMORY"],
        findings.map { row in
          [
            row.kindLabel, row.title, row.project, row.reasonText,
            String(row.pids.count), memory(row.residentBytes),
          ]
        })
    ]
    lines.append("")
    lines.append("A Cleanup of all of it would free \(memory(reclaimableBytes)).")
    if !activityObserved {
      lines.append("Idle dev servers are judged only while the app is running.")
    }
    return lines.joined(separator: "\n")
  }
}

extension RequestsReport {
  func table(now: Date) -> String {
    columns(
      ["ID", "STATUS", "FILED", "BY", "PROCS", "OUTCOME", "REASON"],
      requests.map { row in
        [
          row.id, row.status, "\(age(of: row.createdAt, now: now)) ago",
          row.requester ?? "-", String(row.pids.count), row.outcome?.text ?? "-",
          row.reason.isEmpty ? "-" : row.reason,
        ]
      })
  }
}
