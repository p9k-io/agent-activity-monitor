import AAMCore
import Foundation

extension Store {
  /// Where CPU time went since `start`, with each Session called by the title that is
  /// remembered for it.
  public func usageReport(since start: Date) throws -> UsageReport {
    let titles = try loadMemory().sessions.compactMapValues(\.title)
    return UsageReport(
      totals: try usageTotals(since: start), peaks: try usagePeaks(since: start), titles: titles)
  }
}
