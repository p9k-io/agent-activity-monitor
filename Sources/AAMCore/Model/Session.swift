import Foundation

/// An AI coding agent program that runs Sessions.
public struct HarnessID: RawRepresentable, Hashable, Sendable, Codable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public static let claudeCode = HarnessID(rawValue: "claude-code")
  public static let codex = HarnessID(rawValue: "codex")
}

public struct SessionID: Hashable, Sendable, Codable, CustomStringConvertible {
  public let harness: HarnessID
  /// The identifier the Harness itself uses for the Session.
  public let value: String

  public init(harness: HarnessID, value: String) {
    self.harness = harness
    self.value = value
  }

  public var description: String { "\(harness.rawValue):\(value)" }
}

/// What a Session is doing, as far as it can be told from outside.
public enum SessionState: String, Sendable, Codable, CaseIterable {
  /// A turn is running.
  case working
  /// The Session asked the person something and waits for the answer.
  case waiting
  /// The turn is over, but work the Session started keeps running in the background.
  case background
  /// The turn is over and nothing is running.
  case idle
  /// The Harness's own record is missing or has a shape this version does not understand.
  case unknown
}

/// The directory a Session works in, identified by its git repository root, or by the working
/// directory when there is none.
public struct Project: Hashable, Sendable, Codable, Identifiable {
  public let root: String

  public init(root: String) {
    self.root = root
  }

  public var id: String { root }

  public var name: String {
    root.split(separator: "/").last.map(String.init) ?? root
  }
}

/// One running instance of a Harness working in a directory on a person's behalf.
public struct Session: Sendable, Equatable, Identifiable {
  public let id: SessionID
  /// The Session's root process.
  public let root: ProcessRecord.Key
  public let project: Project
  public let workingDirectory: String
  public let title: String?
  public let state: SessionState
  public let lastActivityAt: Date?
  /// The command that reopens the Session with its conversation intact.
  public let resumeCommand: String?
  /// Environment variables and values that mark a process as belonging to this Session.
  public let markers: [String: String]

  public init(
    id: SessionID,
    root: ProcessRecord.Key,
    project: Project,
    workingDirectory: String,
    title: String?,
    state: SessionState,
    lastActivityAt: Date?,
    resumeCommand: String?,
    markers: [String: String]
  ) {
    self.id = id
    self.root = root
    self.project = project
    self.workingDirectory = workingDirectory
    self.title = title
    self.state = state
    self.lastActivityAt = lastActivityAt
    self.resumeCommand = resumeCommand
    self.markers = markers
  }
}
