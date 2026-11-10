/// Where a Session's terminal lives: in which Host, and where inside it when the Host tells.
public struct HostPlace: Sendable, Equatable {
  /// The Host by the name of its application.
  public let host: String
  /// The Host's own process, which is what is brought to the front.
  public let hostPID: Int32
  /// Where in the Host the terminal is, in the Host's own names.
  public let location: String?
  /// What the Host needs to bring that place to the front. It means nothing to anyone else.
  public let reference: [String: String]

  public init(host: String, hostPID: Int32, location: String?, reference: [String: String]) {
    self.host = host
    self.hostPID = hostPID
    self.location = location
    self.reference = reference
  }

  public var label: String {
    location.map { "\(host) › \($0)" } ?? host
  }
}

/// Knows one Host: where in it a Session's terminal is, and how to bring that to the front.
public protocol HostAdapter: Sendable {
  /// Adds what this Host knows to the places of the Sessions that live in it. A Session it
  /// knows nothing about keeps the place it had.
  func refine(_ places: [SessionID: HostPlace], sessions: [Session]) -> [SessionID: HostPlace]

  /// Brings a place to the front inside the Host. False when the place is not one of this
  /// Host's.
  func show(_ place: HostPlace) -> Bool
}

/// Finds the Host of each Session from the process tree alone: the application the Session's
/// terminal runs in.
public enum HostFinder {
  public static func places(of sessions: [Session], in tree: ProcessTree) -> [SessionID: HostPlace]
  {
    var places: [SessionID: HostPlace] = [:]
    for session in sessions {
      let applications = tree.ancestors(of: session.root.pid).filter(\.isInsideApplication)
      guard let nearest = applications.first else { continue }
      let name = nearest.applicationOrName
      // A helper inside the application's bundle leads up to the application itself.
      let host = applications.last { $0.applicationOrName == name } ?? nearest
      places[session.id] = HostPlace(host: name, hostPID: host.pid, location: nil, reference: [:])
    }
    return places
  }
}

extension ProcessRecord {
  fileprivate var isInsideApplication: Bool {
    executablePath.contains(".app/")
  }
}
