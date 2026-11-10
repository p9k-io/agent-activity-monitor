import AAMCore
import SwiftUI

/// Cleanup requests: those waiting for a decision, and what was decided about the others.
struct RequestsView: View {
  @Environment(AppModel.self) private var model

  /// How many decided requests are listed.
  private static let decidedLimit = 20

  var body: some View {
    let pending = model.pendingRequests
    let decided = model.requests.filter { $0.status != .pending }
      .suffix(Self.decidedLimit).reversed()
    if model.requests.isEmpty {
      ContentUnavailableView(
        "No Cleanup requests",
        systemImage: "tray",
        description: Text(
          "A Session asks with `aam request-cleanup`. Nothing is ended until you approve it here."
        ))
    } else {
      List {
        if !pending.isEmpty {
          Section("Waiting for your decision") {
            ForEach(pending) { request in
              PendingRow(request: request)
            }
          }
        }
        if !decided.isEmpty {
          Section("Decided") {
            ForEach(Array(decided)) { request in
              DecidedRow(request: request, now: model.now)
            }
          }
        }
      }
    }
  }
}

private struct PendingRow: View {
  @Environment(AppModel.self) private var model
  let request: CleanupRequest

  var body: some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: model.proposer?.origin(of: request) ?? "Cleanup request \(request.id)")
          .lineLimit(1)
        Text(verbatim: request.reason.isEmpty ? "No reason was given." : request.reason)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
        Text(verbatim: "\(request.id) · \(count) · filed \(age) ago")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button("Deny") { model.deny(request) }
        .accessibilityIdentifier("request.deny")
      Button("Review…") { model.propose { $0.answering(request) } }
        .accessibilityIdentifier("request.review")
    }
    .padding(.vertical, 2)
  }

  private var count: String {
    request.targets.count == 1 ? "1 process" : "\(request.targets.count) processes"
  }

  private var age: String {
    Format.span(from: request.createdAt, to: model.now)
  }
}

private struct DecidedRow: View {
  let request: CleanupRequest
  let now: Date

  var body: some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: request.reason.isEmpty ? "Cleanup request \(request.id)" : request.reason)
          .lineLimit(1)
        Text(verbatim: detail)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Text(request.status == .done ? "Done" : "Denied")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var detail: String {
    var parts = [request.id]
    if let decidedAt = request.decidedAt {
      parts.append("\(Format.span(from: decidedAt, to: now)) ago")
    }
    if let outcome = request.outcome {
      parts.append(outcome.text)
    }
    return parts.joined(separator: " · ")
  }
}
