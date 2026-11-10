import AAMCore
import Foundation
import SQLite3

public struct StoreError: Error, CustomStringConvertible {
  public let description: String
}

/// Keeps what the app remembers in one SQLite file, shared by the app and the command line tool.
///
/// The file holds identifiers, paths and times. It never holds command lines, environment
/// values or anything a Session said.
public final class Store: @unchecked Sendable {
  /// Guards the connection: one statement sequence at a time, whoever calls.
  private let lock = NSLock()
  private let connection: OpaquePointer

  /// Where the store lives: the path in `AAM_STORE` when it is set, otherwise the app's folder
  /// in Application Support.
  public static var defaultURL: URL {
    if let path = ProcessInfo.processInfo.environment["AAM_STORE"], !path.isEmpty {
      return URL(fileURLWithPath: path)
    }
    return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("io.p9k.agent-activity-monitor", isDirectory: true)
      .appendingPathComponent("aam.sqlite")
  }

  public init(url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    var opened: OpaquePointer?
    let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
    guard sqlite3_open_v2(url.path, &opened, flags, nil) == SQLITE_OK, let opened else {
      let message = opened.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open"
      sqlite3_close_v2(opened)
      throw StoreError(description: "\(url.path): \(message)")
    }
    connection = opened
    sqlite3_busy_timeout(connection, 2000)
    do {
      try execute("PRAGMA journal_mode = WAL")
      try migrate()
    } catch {
      sqlite3_close_v2(connection)
      throw error
    }
    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }

  deinit {
    sqlite3_close_v2(connection)
  }

  // MARK: Memory

  public func loadMemory() throws -> Memory {
    try locked {
      var memory = Memory.empty
      try rows(
        "SELECT harness, id, project_root, title, markers, last_seen_at, ended_at FROM sessions"
      ) { row in
        let id = SessionID(harness: HarnessID(rawValue: row.text(0)), value: row.text(1))
        memory.sessions[id] = Memory.PastSession(
          project: Project(root: row.text(2)),
          title: row.optionalText(3),
          markers: (try? JSONDecoder().decode([String: String].self, from: Data(row.text(4).utf8)))
            ?? [:],
          lastSeenAt: row.date(5),
          endedAt: row.optionalDate(6))
      }
      try rows("SELECT pid, started_at, harness, session_id, project_root FROM lineage") { row in
        memory.lineage[row.key(0, 1)] = Memory.Lineage(
          session: SessionID(harness: HarnessID(rawValue: row.text(2)), value: row.text(3)),
          project: Project(root: row.text(4)))
      }
      try rows("SELECT pid, started_at, last_busy_at FROM activity") { row in
        memory.lastBusyAt[row.key(0, 1)] = row.date(2)
      }
      try rows("SELECT value FROM meta WHERE key = 'activity_as_of'") { row in
        memory.activityAsOf = Double(row.text(0)).map(Date.init(timeIntervalSinceReferenceDate:))
      }
      return memory
    }
  }

  /// Replaces what was remembered with `memory`, in one transaction.
  public func save(_ memory: Memory) throws {
    try locked {
      try execute("BEGIN IMMEDIATE")
      do {
        try execute("DELETE FROM sessions; DELETE FROM lineage; DELETE FROM activity")
        for (id, session) in memory.sessions {
          let markers = String(
            decoding: (try? JSONEncoder().encode(session.markers)) ?? Data("{}".utf8),
            as: UTF8.self)
          try run(
            "INSERT INTO sessions VALUES (?, ?, ?, ?, ?, ?, ?)",
            .text(id.harness.rawValue), .text(id.value), .text(session.project.root),
            session.title.map(Value.text) ?? .null, .text(markers), .date(session.lastSeenAt),
            session.endedAt.map(Value.date) ?? .null)
        }
        for (key, lineage) in memory.lineage {
          try run(
            "INSERT INTO lineage VALUES (?, ?, ?, ?, ?)",
            .integer(Int64(key.pid)), .date(key.startedAt),
            .text(lineage.session.harness.rawValue), .text(lineage.session.value),
            .text(lineage.project.root))
        }
        for (key, date) in memory.lastBusyAt {
          try run(
            "INSERT INTO activity VALUES (?, ?, ?)",
            .integer(Int64(key.pid)), .date(key.startedAt), .date(date))
        }
        try run("DELETE FROM meta WHERE key = 'activity_as_of'")
        if let measured = memory.activityAsOf {
          try run(
            "INSERT INTO meta VALUES ('activity_as_of', ?)",
            .text(String(measured.timeIntervalSinceReferenceDate)))
        }
        try execute("COMMIT")
      } catch {
        try? execute("ROLLBACK")
        throw error
      }
    }
  }

  // MARK: Cleanup requests

  public func add(_ request: CleanupRequest) throws {
    try locked {
      try run(
        "INSERT INTO requests VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        .text(request.id), .date(request.createdAt),
        request.requester.map { .text($0.harness.rawValue) } ?? .null,
        request.requester.map { .text($0.value) } ?? .null,
        .text(request.reason), .text(json(request.targets)), .text(request.status.rawValue),
        request.decidedAt.map(Value.date) ?? .null,
        request.outcome.map { .text(json($0)) } ?? .null)
    }
  }

  /// Records a decision: the status, when it was made and what the Cleanup did.
  public func update(_ request: CleanupRequest) throws {
    try locked {
      try run(
        "UPDATE requests SET status = ?, decided_at = ?, outcome = ? WHERE id = ?",
        .text(request.status.rawValue), request.decidedAt.map(Value.date) ?? .null,
        request.outcome.map { .text(json($0)) } ?? .null, .text(request.id))
    }
  }

  /// Cleanup requests, the oldest first. With a status, only those in it.
  public func requests(status: CleanupRequest.Status? = nil) throws -> [CleanupRequest] {
    try locked {
      var found: [CleanupRequest] = []
      try rows(
        """
        SELECT id, created_at, requester_harness, requester_id, reason, targets, status,
               decided_at, outcome
        FROM requests ORDER BY created_at, id
        """
      ) { row in
        let request = CleanupRequest(
          id: row.text(0),
          createdAt: row.date(1),
          requester: row.optionalText(2).flatMap { harness in
            row.optionalText(3).map {
              SessionID(harness: HarnessID(rawValue: harness), value: $0)
            }
          },
          reason: row.text(4),
          targets: decode([ProcessRecord.Key].self, from: row.text(5)) ?? [],
          status: CleanupRequest.Status(rawValue: row.text(6)) ?? .pending,
          decidedAt: row.optionalDate(7),
          outcome: row.optionalText(8).flatMap {
            decode(CleanupRequest.Outcome.self, from: $0)
          })
        if status == nil || request.status == status {
          found.append(request)
        }
      }
      return found
    }
  }

  // MARK: History

  /// Adds CPU time to what is recorded for the same minute, Session and kind of process, and
  /// keeps the larger of the two peaks.
  public func record(_ buckets: [HistoryBucket]) throws {
    guard !buckets.isEmpty else { return }
    try locked {
      try execute("BEGIN IMMEDIATE")
      do {
        for bucket in buckets {
          try run(
            """
            INSERT INTO history VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (minute, project_root, harness, session_id, kind) DO UPDATE SET
              cpu_seconds = cpu_seconds + excluded.cpu_seconds,
              peak_rss = max(peak_rss, excluded.peak_rss)
            """,
            .date(bucket.minute), .text(bucket.project.root),
            .text(bucket.session?.harness.rawValue ?? ""), .text(bucket.session?.value ?? ""),
            .text(bucket.kind.rawValue), .real(bucket.cpuSeconds),
            .integer(Int64(clamping: bucket.peakResidentBytes)))
        }
        try execute("COMMIT")
      } catch {
        try? execute("ROLLBACK")
        throw error
      }
    }
  }

  /// The CPU time used since `start`, per Session and kind of process.
  public func usageTotals(since start: Date) throws -> [UsageTotal] {
    try locked {
      var totals: [UsageTotal] = []
      try rows(
        """
        SELECT project_root, harness, session_id, kind, SUM(cpu_seconds) FROM history
        WHERE minute >= ? GROUP BY project_root, harness, session_id, kind
        ORDER BY project_root, harness, session_id, kind
        """, .date(start)
      ) { row in
        totals.append(
          UsageTotal(
            project: Project(root: row.text(0)), session: row.session(1, 2),
            kind: ProcessKind(rawValue: row.text(3)) ?? .other, cpuSeconds: row.double(4)))
      }
      return totals
    }
  }

  /// The most memory each Session held in one minute since `start`.
  public func usagePeaks(since start: Date) throws -> [UsagePeak] {
    try locked {
      var peaks: [UsagePeak] = []
      try rows(
        """
        SELECT project_root, harness, session_id, MAX(held) FROM (
          SELECT project_root, harness, session_id, SUM(peak_rss) AS held FROM history
          WHERE minute >= ? GROUP BY minute, project_root, harness, session_id)
        GROUP BY project_root, harness, session_id ORDER BY project_root, harness, session_id
        """, .date(start)
      ) { row in
        peaks.append(
          UsagePeak(
            project: Project(root: row.text(0)), session: row.session(1, 2),
            residentBytes: UInt64(clamping: row.integer(3))))
      }
      return peaks
    }
  }

  /// Drops history from before `cutoff`, and Cleanup requests decided before it. A request
  /// that still waits for a decision is kept however old it is.
  public func prune(before cutoff: Date) throws {
    try locked {
      try run("DELETE FROM history WHERE minute < ?", .date(cutoff))
      try run(
        "DELETE FROM requests WHERE status != 'pending' AND decided_at < ?", .date(cutoff))
    }
  }

  private func json(_ value: some Encodable) -> String {
    String(decoding: (try? JSONEncoder().encode(value)) ?? Data(), as: UTF8.self)
  }

  private func decode<T: Decodable>(_ type: T.Type, from text: String) -> T? {
    try? JSONDecoder().decode(type, from: Data(text.utf8))
  }

  // MARK: Schema

  private func migrate() throws {
    try execute(
      """
      CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS sessions (
        harness TEXT NOT NULL, id TEXT NOT NULL, project_root TEXT NOT NULL, title TEXT,
        markers TEXT NOT NULL, last_seen_at REAL NOT NULL, ended_at REAL,
        PRIMARY KEY (harness, id));
      CREATE TABLE IF NOT EXISTS lineage (
        pid INTEGER NOT NULL, started_at REAL NOT NULL, harness TEXT NOT NULL,
        session_id TEXT NOT NULL, project_root TEXT NOT NULL,
        PRIMARY KEY (pid, started_at));
      CREATE TABLE IF NOT EXISTS requests (
        id TEXT PRIMARY KEY, created_at REAL NOT NULL, requester_harness TEXT,
        requester_id TEXT, reason TEXT NOT NULL, targets TEXT NOT NULL, status TEXT NOT NULL,
        decided_at REAL, outcome TEXT);
      CREATE TABLE IF NOT EXISTS activity (
        pid INTEGER NOT NULL, started_at REAL NOT NULL, last_busy_at REAL NOT NULL,
        PRIMARY KEY (pid, started_at));
      CREATE TABLE IF NOT EXISTS history (
        minute REAL NOT NULL, project_root TEXT NOT NULL, harness TEXT NOT NULL,
        session_id TEXT NOT NULL, kind TEXT NOT NULL, cpu_seconds REAL NOT NULL,
        peak_rss INTEGER NOT NULL,
        PRIMARY KEY (minute, project_root, harness, session_id, kind));
      """)
  }

  // MARK: SQLite

  private enum Value {
    case text(String)
    case real(Double)
    case integer(Int64)
    case null

    /// A date is stored the way `Date` holds it, so that it reads back as exactly the same
    /// value. Converting to another epoch and back can change the last bit, and a process is
    /// looked up by its start time.
    static func date(_ date: Date) -> Value {
      .real(date.timeIntervalSinceReferenceDate)
    }
  }

  /// A row being read. Columns are addressed by position.
  private struct Row {
    let statement: OpaquePointer

    func text(_ column: Int32) -> String {
      sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
    }

    func optionalText(_ column: Int32) -> String? {
      sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : text(column)
    }

    func date(_ column: Int32) -> Date {
      Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, column))
    }

    func optionalDate(_ column: Int32) -> Date? {
      sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : date(column)
    }

    func double(_ column: Int32) -> Double {
      sqlite3_column_double(statement, column)
    }

    func integer(_ column: Int32) -> Int64 {
      sqlite3_column_int64(statement, column)
    }

    /// The Session in two columns, or nil when they are empty: what belongs to no Session.
    func session(_ harness: Int32, _ id: Int32) -> SessionID? {
      let value = text(id)
      return value.isEmpty
        ? nil : SessionID(harness: HarnessID(rawValue: text(harness)), value: value)
    }

    func key(_ pid: Int32, _ startedAt: Int32) -> ProcessRecord.Key {
      ProcessRecord.Key(pid: sqlite3_column_int(statement, pid), startedAt: date(startedAt))
    }
  }

  private func locked<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }

  private func execute(_ sql: String) throws {
    guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
  }

  private func run(_ sql: String, _ values: Value...) throws {
    let statement = try prepare(sql, values)
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
  }

  private func rows(_ sql: String, _ values: Value..., read: (Row) -> Void) throws {
    let statement = try prepare(sql, values)
    defer { sqlite3_finalize(statement) }
    while true {
      switch sqlite3_step(statement) {
      case SQLITE_ROW: read(Row(statement: statement))
      case SQLITE_DONE: return
      default: throw failure()
      }
    }
  }

  private func prepare(_ sql: String, _ values: [Value]) throws -> OpaquePointer {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement
    else { throw failure() }
    // SQLite copies the text before the call returns.
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    for (index, value) in values.enumerated() {
      let position = Int32(index + 1)
      switch value {
      case .text(let text): sqlite3_bind_text(statement, position, text, -1, transient)
      case .real(let number): sqlite3_bind_double(statement, position, number)
      case .integer(let number): sqlite3_bind_int64(statement, position, number)
      case .null: sqlite3_bind_null(statement, position)
      }
    }
    return statement
  }

  private func failure() -> StoreError {
    StoreError(description: String(cString: sqlite3_errmsg(connection)))
  }
}
