import Foundation

/// What is remembered from earlier observations.
///
/// When a Session ends, its surviving processes are re-parented and nothing in the process table
/// links them to it any more. Memory keeps that link, and keeps the Projects that had Sessions.
public struct Memory: Sendable, Equatable {
  /// A Session that was seen, running or ended.
  public struct PastSession: Sendable, Equatable, Codable {
    public var project: Project
    public var title: String?
    public var markers: [String: String]
    public var lastSeenAt: Date
    /// Nil while the Session is running.
    public var endedAt: Date?

    public init(
      project: Project, title: String?, markers: [String: String], lastSeenAt: Date, endedAt: Date?
    ) {
      self.project = project
      self.title = title
      self.markers = markers
      self.lastSeenAt = lastSeenAt
      self.endedAt = endedAt
    }
  }

  /// The Session a process was seen to belong to.
  public struct Lineage: Sendable, Equatable, Codable {
    public var session: SessionID
    public var project: Project

    public init(session: SessionID, project: Project) {
      self.session = session
      self.project = project
    }
  }

  public var sessions: [SessionID: PastSession] = [:]
  public var lineage: [ProcessRecord.Key: Lineage] = [:]
  /// When each followed process last used a noticeable amount of CPU.
  public var lastBusyAt: [ProcessRecord.Key: Date] = [:]
  /// When CPU use was last measured. `lastBusyAt` says nothing about the time after it.
  public var activityAsOf: Date?

  /// A pause in measuring longer than this means anything may have happened meanwhile.
  public static let longestActivityGap: TimeInterval = 120

  public static let empty = Memory()

  public init() {}

  /// Remembers what an observation shows.
  ///
  /// - Parameters:
  ///   - usage: CPU use since the previous observation, when there was one.
  ///   - busyAbove: CPU use, in percent of one core, from which a process counts as busy.
  public mutating func absorb(
    _ observation: Reading, usage: Usage? = nil, busyAbove: Double = 1
  ) {
    let now = observation.snapshot.takenAt
    var live: Set<SessionID> = []
    var followed: [ProcessRecord.Key] = []

    // A Session whose root process reports another identifier than before, as after starting
    // over, is the same Session. What was remembered for it goes on under the new identifier
    // instead of being left behind by a Session that seems to have ended.
    let reported = Set(observation.sessions.map(\.id))
    for session in observation.sessions {
      guard let before = lineage[session.root]?.session, before != session.id,
        !reported.contains(before)
      else { continue }
      for (key, entry) in lineage where entry.session == before {
        lineage[key] = Lineage(session: session.id, project: entry.project)
      }
      sessions[before] = nil
    }

    for project in observation.inventory.projects {
      for group in project.sessions {
        let session = group.session
        live.insert(session.id)
        sessions[session.id] = PastSession(
          project: session.project, title: session.title, markers: session.markers,
          lastSeenAt: now, endedAt: nil)
        for attributed in group.processes {
          lineage[attributed.process.key] = Lineage(session: session.id, project: session.project)
          followed.append(attributed.process.key)
        }
      }
      followed.append(contentsOf: project.loose.map(\.process.key))
    }

    for (id, session) in sessions where !live.contains(id) && session.endedAt == nil {
      sessions[id]?.endedAt = now
    }

    if let usage {
      // Whoever only looks, without measuring CPU, learns nothing about activity.
      let resumed = activityAsOf.map { now.timeIntervalSince($0) > Self.longestActivityGap } ?? true
      for key in followed
      where resumed || lastBusyAt[key] == nil || usage.cpuPercent(of: key) >= busyAbove {
        lastBusyAt[key] = now
      }
      activityAsOf = now
    }

    let alive = Set(observation.snapshot.processes.map(\.key))
    lineage = lineage.filter { alive.contains($0.key) }
    lastBusyAt = lastBusyAt.filter { alive.contains($0.key) }
  }

  public mutating func forget(sessionsEndedBefore date: Date) {
    sessions = sessions.filter { _, session in
      guard let endedAt = session.endedAt else { return true }
      return endedAt >= date
    }
  }
}
