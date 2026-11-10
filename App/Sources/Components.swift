import AAMCore
import SwiftUI

/// A Session's state as a small coloured label.
struct StateBadge: View {
  let state: SessionState

  var body: some View {
    Text(state.label)
      .font(.caption)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(color.opacity(0.18), in: Capsule())
      .foregroundStyle(color)
  }

  private var color: Color {
    switch state {
    case .working: .green
    case .waiting: .orange
    case .background: .blue
    case .idle, .unknown: .secondary
    }
  }
}

/// A number with its caption, for the summary at the top of the overview.
struct Tile: View {
  let title: String
  let value: String
  let detail: String

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.title2.weight(.semibold))
        .monospacedDigit()
      Text(detail)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
  }
}

extension Culprit.Owner {
  /// Whom a Culprit belongs to, in a few words.
  var label: String {
    switch self {
    case .session(let id, let project): "\(id.harness.label) in \(project.name)"
    case .project(let project): "Project \(project.name)"
    case .none: "Not from a Session"
    }
  }
}

extension HarnessID {
  var label: String {
    switch self {
    case .claudeCode: "Claude Code"
    case .codex: "Codex"
    default: rawValue
    }
  }
}

extension Session {
  /// The Session's title, or its Project's name when it has none.
  var displayTitle: String { title ?? project.name }

  func lastActive(now: Date) -> String {
    if state == .working { return "now" }
    guard let lastActivityAt else { return "–" }
    return "\(Format.span(from: lastActivityAt, to: now)) ago"
  }
}

extension StaleFinding.Kind {
  /// The kind as a heading over several findings.
  var heading: String {
    switch self {
    case .idleSession: "Idle sessions"
    case .ownerlessLeftover: "Ownerless leftovers"
    case .forgottenInducedLoad: "Forgotten induced load"
    case .idleDevServer: "Idle dev servers"
    }
  }
}
