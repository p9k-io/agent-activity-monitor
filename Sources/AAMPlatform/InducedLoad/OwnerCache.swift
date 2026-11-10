import AAMCore
import Synchronization

/// Remembers, for helper processes, whom each one works for. Finding that out means listing a
/// helper's files, and a helper does not change hands.
final class OwnerCache: Sendable {
  private let owners = Mutex<[ProcessRecord.Key: String?]>([:])

  /// The owner of each helper, looked up with `find` only for helpers not seen before.
  /// Helpers that are gone are forgotten.
  func owners(
    of helpers: [ProcessRecord], find: (ProcessRecord) -> String?
  ) -> [ProcessRecord.Key: String?] {
    var result: [ProcessRecord.Key: String?] = [:]
    for helper in helpers {
      if let known = owners.withLock({ $0[helper.key] }) {
        result[helper.key] = known
      } else {
        let owner = find(helper)
        owners.withLock { $0[helper.key] = .some(owner) }
        result[helper.key] = .some(owner)
      }
    }
    owners.withLock { $0 = result }
    return result
  }
}

extension OpenFileListing {
  /// The first file a process holds open or has mapped that `matches`. Open files are few and
  /// cheap to list; mapped files are many, so they come second.
  func firstFile(of pid: Int32, where matches: (String) -> Bool) -> String? {
    openFiles(of: pid).first(where: matches) ?? firstMappedFile(of: pid, where: matches)
  }
}
