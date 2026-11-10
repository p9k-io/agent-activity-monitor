/// The CPU time one kind of process used for a Session, or loose in a Project, over a period.
public struct UsageTotal: Sendable, Equatable {
  public let project: Project
  public let session: SessionID?
  public let kind: ProcessKind
  public let cpuSeconds: Double

  public init(project: Project, session: SessionID?, kind: ProcessKind, cpuSeconds: Double) {
    self.project = project
    self.session = session
    self.kind = kind
    self.cpuSeconds = cpuSeconds
  }
}

/// The most memory a Session, or what is loose in a Project, held over a period.
public struct UsagePeak: Sendable, Equatable {
  public let project: Project
  public let session: SessionID?
  public let residentBytes: UInt64

  public init(project: Project, session: SessionID?, residentBytes: UInt64) {
    self.project = project
    self.session = session
    self.residentBytes = residentBytes
  }
}

/// Where CPU time went over a period: per Session and per Project, the heaviest first.
public struct UsageReport: Sendable, Equatable {
  public struct KindShare: Sendable, Equatable {
    public let kind: ProcessKind
    public let cpuSeconds: Double
  }

  /// One Session, or what belongs to a Project but to no single Session.
  public struct Row: Sendable, Equatable, Identifiable {
    public let project: Project
    public let session: SessionID?
    /// The Session's title, or its Project's name when it has none.
    public let title: String
    public let cpuSeconds: Double
    public let peakResidentBytes: UInt64
    /// What the CPU time went on, the largest share first.
    public let byKind: [KindShare]

    public var id: String { "\(project.root)|\(session?.description ?? "")" }
  }

  public struct ProjectTotal: Sendable, Equatable, Identifiable {
    public let project: Project
    public let cpuSeconds: Double

    public var id: String { project.root }
  }

  public let rows: [Row]
  public let projects: [ProjectTotal]

  public var cpuSeconds: Double {
    rows.reduce(0) { $0 + $1.cpuSeconds }
  }

  /// - Parameter titles: The titles of the Sessions that have one.
  public init(totals: [UsageTotal], peaks: [UsagePeak], titles: [SessionID: String]) {
    struct Owner: Hashable {
      let project: Project
      let session: SessionID?
    }
    let peakOf = Dictionary(
      peaks.map { (Owner(project: $0.project, session: $0.session), $0.residentBytes) },
      uniquingKeysWith: max)
    rows = Dictionary(grouping: totals) { Owner(project: $0.project, session: $0.session) }
      .map { owner, parts in
        Row(
          project: owner.project, session: owner.session,
          title: owner.session.map { titles[$0] ?? owner.project.name }
            ?? "Not tied to one Session",
          cpuSeconds: parts.reduce(0) { $0 + $1.cpuSeconds },
          peakResidentBytes: peakOf[owner] ?? 0,
          byKind: Dictionary(grouping: parts, by: \.kind)
            .map { kind, shares in
              KindShare(kind: kind, cpuSeconds: shares.reduce(0) { $0 + $1.cpuSeconds })
            }
            .sorted { ($1.cpuSeconds, $0.kind.rawValue) < ($0.cpuSeconds, $1.kind.rawValue) })
      }
      .sorted { ($1.cpuSeconds, $0.id) < ($0.cpuSeconds, $1.id) }
    projects = Dictionary(grouping: rows, by: \.project)
      .map { project, members in
        ProjectTotal(project: project, cpuSeconds: members.reduce(0) { $0 + $1.cpuSeconds })
      }
      .sorted { ($1.cpuSeconds, $0.project.root) < ($0.cpuSeconds, $1.project.root) }
  }
}
