import AAMCore
import AppKit

/// WebKit runs the pages of every application in helper processes started by the system, so
/// the process table does not say whose they are. The storage a helper uses does: it lives in
/// `~/Library/WebKit/<application>`, and the helper has files from it mapped or open.
public final class WebContentLinker: InducedLoadLinker {
  private let files: any OpenFileListing
  private let applicationName: @Sendable (String) -> String?
  private let cache = OwnerCache()

  /// - Parameter applicationName: The name a person knows an application by, given its
  ///   identifier. Nil when the system does not know the application.
  public init(
    files: any OpenFileListing = LibprocOpenFiles(),
    applicationName: @escaping @Sendable (String) -> String? = WebContentLinker.installedName
  ) {
    self.files = files
    self.applicationName = applicationName
  }

  public func inducedLoad(in snapshot: Snapshot) -> [InducedLoad] {
    let helpers = snapshot.processes.filter { $0.name.hasPrefix("com.apple.WebKit.") }
    let owners = cache.owners(of: helpers) { helper in
      files.firstFile(of: helper.pid) { Self.application(in: $0) != nil }
        .flatMap(Self.application)
    }
    var members: [String: [ProcessRecord.Key]] = [:]
    for helper in helpers {
      if let owner = owners[helper.key] ?? nil {
        members[owner, default: []].append(helper.key)
      }
    }
    return members.sorted { $0.key < $1.key }.map { owner, processes in
      InducedLoad(
        id: "web-content:\(owner)",
        kind: .webContent(application: owner),
        title: "Web content of \(applicationName(owner) ?? owner)",
        processes: processes)
    }
  }

  /// The application identifier in `…/Library/WebKit/<application>/…`.
  private static func application(in path: String) -> String? {
    let parts = path.split(separator: "/")
    guard let folder = parts.firstIndex(of: "WebKit"), folder > 0,
      parts[folder - 1] == "Library", parts.indices.contains(folder + 1)
    else { return nil }
    return String(parts[folder + 1])
  }

  /// The name of an installed application, as the Finder shows it.
  public static func installedName(of identifier: String) -> String? {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else {
      return nil
    }
    let name = FileManager.default.displayName(atPath: url.path)
    return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
  }
}
