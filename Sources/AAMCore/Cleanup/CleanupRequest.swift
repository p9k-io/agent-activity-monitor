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
    public var killed: Int
    public var survived: Int
    public var refused: Int

    public init(ended: Int, killed: Int, survived: Int, refused: Int) {
      self.ended = ended
      self.killed = killed
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
    self.reason = String(reason.prefix(Self.reasonLimit))
    self.targets = targets
    self.status = status
    self.decidedAt = decidedAt
    self.outcome = outcome
  }
}
