import AAMCore
import Synchronization

/// WebKit runs the pages of every application in helper processes started by the system, so
/// the process table does not say whose they are. The storage a helper uses does: it lives in
/// `~/Library/WebKit/<application>`, and the helper has files from it mapped or open.
public final class WebContentLinker: InducedLoadLinker {
  private let files: any OpenFileListing
  /// The application of each helper, once looked up. Finding it means walking the helper's
  /// memory map, and a helper does not change hands.
  private let owners = Mutex<[ProcessRecord.Key: String?]>([:])

  public init(files: any OpenFileListing = LibprocOpenFiles()) {
    self.files = files
  }

  public func inducedLoad(in snapshot: Snapshot) -> [InducedLoad] {
    let helpers = snapshot.processes.filter { $0.name.hasPrefix("com.apple.WebKit.") }
    var members: [String: [ProcessRecord.Key]] = [:]
    for helper in helpers {
      let owner: String?
      if let known = owners.withLock({ $0[helper.key] }) {
        owner = known
      } else {
        owner = self.owner(of: helper.pid)
        owners.withLock { $0[helper.key] = .some(owner) }
      }
      if let owner {
        members[owner, default: []].append(helper.key)
      }
    }
    let alive = Set(helpers.map(\.key))
    owners.withLock { known in known = known.filter { alive.contains($0.key) } }
    return members.sorted { $0.key < $1.key }.map { owner, processes in
      InducedLoad(
        id: "web-content:\(owner)", title: "Web content of \(owner)", processes: processes)
    }
  }

  private func owner(of pid: Int32) -> String? {
    // Open files are few and cheap to list; mapped files are many, so they come second.
    files.openFiles(of: pid).lazy.compactMap(Self.application).first
      ?? files.firstMappedFile(of: pid) { Self.application(in: $0) != nil }
      .flatMap(Self.application)
  }

  /// The application identifier in `…/Library/WebKit/<application>/…`.
  private static func application(in path: String) -> String? {
    let parts = path.split(separator: "/")
    guard let folder = parts.firstIndex(of: "WebKit"), folder > 0,
      parts[folder - 1] == "Library", parts.indices.contains(folder + 1)
    else { return nil }
    return String(parts[folder + 1])
  }
}
