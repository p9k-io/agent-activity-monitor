import Foundation

/// A proposal to clean up specific targets, filed by a Session or a script, waiting for a
/// person's decision.
public struct CleanupRequest: Sendable, Equatable, Identifiable, Codable {
  public enum Status: String, Sendable, Codable, CaseIterable {
    /// Nobody has decided yet.
    case pending
    /// A person approved it and the Cleanup ran.
    case done
    /// A person turned it down.
    case denied
  }

  /// What the Cleanup did, in numbers of processes.
  public struct Outcome: Sendable, Equatable, Codable {
    public var ended: Int
    public var endedByForce: Int
    public var survived: Int
    public var refused: Int

    public init(ended: Int, endedByForce: Int, survived: Int, refused: Int) {
      self.ended = ended
      self.endedByForce = endedByForce
      self.survived = survived
      self.refused = refused
    }
  }

  /// The longest reason that is kept.
  public static let reasonLimit = 500

  public let id: String
  public let createdAt: Date
  /// The Session that filed the request, or nil when it came from outside any Session.
  public let requester: SessionID?
  public let reason: String
  /// The processes asked for. What they started is cleaned up with them.
  public let targets: [ProcessRecord.Key]
  public var status: Status
  public var decidedAt: Date?
  public var outcome: Outcome?

  public init(
    id: String,
    createdAt: Date,
    requester: SessionID?,
    reason: String,
    targets: [ProcessRecord.Key],
    status: Status = .pending,
    decidedAt: Date? = nil,
    outcome: Outcome? = nil
  ) {
    self.id = id
    self.createdAt = createdAt
    self.requester = requester
    self.reason = Self.singleLine(reason)
    self.targets = targets
    self.status = status
    self.decidedAt = decidedAt
    self.outcome = outcome
  }

  /// The reason is written by whoever files the request and is shown in a terminal and in the
  /// app next to what a person is asked to confirm. So it is kept to one line of plain text:
  /// whatever breaks a line becomes a space, and control and formatting characters, which
  /// can hide or reorder what is shown, are dropped. The limit counts what is stored, because
  /// one visible character can be made of any number of them.
  private static func singleLine(_ text: String) -> String {
    var line = String.UnicodeScalarView()
    for scalar in text.unicodeScalars {
      guard line.count < reasonLimit else { break }
      switch scalar.properties.generalCategory {
      case .lineSeparator, .paragraphSeparator:
        line.append(" ")
      case .control:
        if scalar == "\n" || scalar == "\r" || scalar == "\t" { line.append(" ") }
      case .format:
        continue
      default:
        line.append(scalar)
      }
    }
    return String(line)
  }
}
