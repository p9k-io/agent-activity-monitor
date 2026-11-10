/// What a person is asked to confirm before a Cleanup: what would be ended, what would be left
/// alone, and what they should know before saying yes.
public struct CleanupProposal: Sendable, Equatable, Identifiable {
  /// How the Cleanup is carried out once it is confirmed.
  public enum Means: Sendable, Equatable {
    /// The processes are asked to exit, and what does not exit is ended by force.
    case endProcesses
    /// The simulator with this device identifier is shut down by Xcode's own tool.
    case shutDownSimulator(device: String)
  }

  /// One process the Cleanup would end, with where it belongs.
  public struct Target: Sendable, Equatable, Identifiable {
    public let process: ProcessRecord
    /// Nil for a process that belongs to no Project.
    public let kind: ProcessKind?
    /// The Session the process is attributed to.
    public let session: Session?

    public var id: ProcessRecord.Key { process.key }

    /// What to call the process. The root of a Session is called by its Harness, because its
    /// file may be named after nothing but a version.
    public var name: String {
      if kind == .harness, let session { return session.id.harness.label }
      return process.name
    }
  }

  /// How to reopen a Session the Cleanup would end.
  public struct Resume: Sendable, Equatable, Identifiable {
    public let session: SessionID
    public let title: String
    public let command: String

    public init(session: SessionID, title: String, command: String) {
      self.session = session
      self.title = title
      self.command = command
    }

    public var id: SessionID { session }
  }

  public let id: String
  /// What is proposed, as a question.
  public let title: String
  /// What it is about, in a sentence or two.
  public let message: String
  /// What a person must know before saying yes.
  public let cautions: [String]
  public let means: Means
  /// The processes asked for. What they started is ended with them.
  public let asked: [ProcessRecord.Key]
  /// What would be ended, each process before the processes it started.
  public let targets: [Target]
  /// What was asked for and is left alone, with the reason.
  public let refused: [CleanupPlan.Refusal]
  public let resume: [Resume]
  /// The Cleanup request the proposal answers, when it answers one.
  public let request: CleanupRequest?

  /// The memory the Cleanup would free.
  public var residentBytes: UInt64 {
    targets.reduce(0) { $0 + $1.process.residentBytes }
  }

  /// False when nothing is left to end.
  public var canProceed: Bool { !targets.isEmpty }
}
