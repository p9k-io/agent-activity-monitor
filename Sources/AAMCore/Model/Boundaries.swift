/// Where the processes of a snapshot come from.
public protocol ProcessSource: Sendable {
  func snapshot() -> Snapshot
}

/// Finds the Sessions of one Harness among the processes of a snapshot.
public protocol HarnessAdapter: Sendable {
  var harness: HarnessID { get }

  /// Names of the environment variables this Harness uses to mark the processes of a Session.
  var markerNames: Set<String> { get }

  /// An adapter never fails: a Session whose record it cannot read is reported as unknown.
  func sessions(in snapshot: Snapshot) -> [Session]
}

/// Decides which Project a directory belongs to.
public protocol ProjectResolver: Sendable {
  func project(for directory: String) -> Project
}
