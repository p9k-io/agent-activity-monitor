import Foundation

/// How facts are worded, so that the app and the command line tool say the same thing.
public enum Format {
  /// The time between two moments in its two largest units: `3d 4h`, `2h 5m`, `7m`, `40s`.
  public static func span(from start: Date, to end: Date) -> String {
    let seconds = max(0, Int(end.timeIntervalSince(start)))
    let (days, hours, minutes) = (seconds / 86_400, seconds % 86_400 / 3600, seconds % 3600 / 60)
    if days > 0 { return "\(days)d \(hours)h" }
    if hours > 0 { return "\(hours)h \(minutes)m" }
    if minutes > 0 { return "\(minutes)m" }
    return "\(seconds)s"
  }

  /// CPU use in percent of one core, so four busy cores read `400.0 %`. The decimal mark
  /// follows the person's region, as it does for memory.
  public static func cpu(_ percent: Double, locale: Locale = .current) -> String {
    let number = percent.formatted(
      .number.precision(.fractionLength(1)).grouping(.never).locale(locale))
    return "\(number) %"
  }

  /// CPU time in hours and minutes. Hours are not turned into days: several cores can use
  /// more CPU time than the clock shows.
  public static func cpuTime(_ seconds: Double) -> String {
    let whole = max(0, Int(seconds))
    let (hours, minutes) = (whole / 3600, whole % 3600 / 60)
    if hours > 0 { return "\(hours)h \(minutes)m" }
    if minutes > 0 { return "\(minutes)m" }
    return "\(whole)s"
  }

  public static func memory(_ bytes: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .memory)
  }
}

extension StaleFinding.Kind {
  public var label: String {
    switch self {
    case .idleSession: "Idle session"
    case .ownerlessLeftover: "Ownerless leftover"
    case .forgottenInducedLoad: "Forgotten induced load"
    case .idleDevServer: "Idle dev server"
    }
  }
}

extension StaleFinding.Reason {
  /// Why something is Stale, in words that fit after its name.
  public func text(now: Date) -> String {
    switch self {
    case .sessionIdle(let since):
      "no activity for \(Format.span(from: since, to: now))"
    case .orphan(_, let since?):
      "its Session ended \(Format.span(from: since, to: now)) ago"
    case .orphan(_, nil):
      "its Session is gone"
    case .zombie(let parent):
      "ended, waiting to be collected by \(parent)"
    case .olderDuplicate(let newest):
      "older copy of \(newest)"
    case .projectQuiet(let since):
      "nothing worked in the Project for \(Format.span(from: since, to: now))"
    case .serverIdle(let since):
      "no CPU use for \(Format.span(from: since, to: now))"
    }
  }
}

extension CleanupPlan.Reason {
  /// Why a process is left alone, in words that fit after its identifier.
  public var explanation: String {
    switch self {
    case .gone: "there is no such process any more"
    case .notYours: "it belongs to another user"
    case .protected: "it must never be ended"
    case .zombie: "it has ended already and waits to be collected by its parent"
    }
  }
}

extension CleanupRequest.Outcome {
  /// What a Cleanup did, as the numbers that are not zero.
  public var text: String {
    let parts = [
      (ended, "exited"), (killed, "ended by force"), (survived, "still running"),
      (refused, "left alone"),
    ]
    .filter { $0.0 > 0 }
    .map { "\($0.0) \($0.1)" }
    return parts.isEmpty ? "Nothing was ended." : parts.joined(separator: ", ") + "."
  }
}

extension HarnessID {
  /// The Harness by the name people know it by.
  public var label: String {
    switch self {
    case .claudeCode: "Claude Code"
    case .codex: "Codex"
    default: rawValue
    }
  }
}

extension Session {
  /// The Session's title, or its Project's name when it has none.
  public var displayTitle: String { title ?? project.name }
}

extension SessionState {
  public var label: String {
    switch self {
    case .working: "Working"
    case .waiting: "Waiting for you"
    case .background: "Background work"
    case .idle: "Idle"
    case .unknown: "Unknown"
    }
  }
}

extension ProcessKind {
  public var label: String {
    switch self {
    case .harness: "Harness"
    case .mcpServer: "MCP server"
    case .devServer: "Dev server"
    case .languageServer: "Language server"
    case .testRunner: "Test runner"
    case .browserContent: "Browser content"
    case .simulator: "Simulator"
    case .virtualMachine: "Virtual machine"
    case .other: "Other"
    }
  }
}

extension Evidence {
  public var label: String {
    switch self {
    case .tree: "Tree"
    case .tagged: "Tagged"
    case .remembered: "Remembered"
    case .inferred: "Inferred"
    }
  }
}
