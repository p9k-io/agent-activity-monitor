import Foundation

/// Decides when load that does not stop is worth telling a person about.
///
/// A stretch of load is told about once. When a Culprit stops being one and becomes one again
/// later, that is a new stretch.
public struct LoadAlerts: Sendable {
  /// How long a Culprit must have been one without a break.
  public var after: Duration
  /// CPU use, in percent of one core, below which a Culprit is not worth an alert.
  public var above: Double

  private var told: Set<String> = []

  public init(after: Duration, above: Double = 0) {
    self.after = after
    self.above = above
  }

  /// The Culprits to tell about now. Each is returned once per stretch of load.
  public mutating func due(_ culprits: [TrackedCulprit], now: Date) -> [TrackedCulprit] {
    // A Culprit that is gone starts over when it comes back.
    told.formIntersection(culprits.map(\.id))
    return culprits.filter { tracked in
      tracked.culprit.cpuPercent >= above
        && now.timeIntervalSince(tracked.hotSince) >= after.seconds
        && told.insert(tracked.id).inserted
    }
  }

  /// What an alert says.
  public static func text(
    for tracked: TrackedCulprit, now: Date, locale: Locale = .current
  ) -> String {
    "\(tracked.culprit.title) has been using "
      + "\(Format.cpu(tracked.culprit.cpuPercent, locale: locale)) CPU "
      + "for \(Format.span(from: tracked.hotSince, to: now))."
  }
}
