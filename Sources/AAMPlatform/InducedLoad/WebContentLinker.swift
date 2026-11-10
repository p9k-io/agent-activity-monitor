import AAMCore

/// WebKit runs the pages of every application in helper processes started by the system, so
/// the process table does not say whose they are. The storage a helper uses does: it lives in
/// `~/Library/WebKit/<application>`, and the helper has files from it mapped or open.
public struct WebContentLinker: InducedLoadLinker {
  private let files: any OpenFileListing

  public init(files: any OpenFileListing = LibprocOpenFiles()) {
    self.files = files
  }

  public func inducedLoad(in snapshot: Snapshot) -> [InducedLoad] {
    var members: [String: [ProcessRecord.Key]] = [:]
    for process in snapshot.processes where process.name.hasPrefix("com.apple.WebKit.") {
      guard let owner = owner(of: process.pid) else { continue }
      members[owner, default: []].append(process.key)
    }
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
