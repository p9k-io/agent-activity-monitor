import AAMCore
import Foundation

/// A Project is the git repository root above a directory. A worktree belongs to the Project of
/// its main repository. Outside any repository the directory is its own Project.
///
/// Paths are handled as plain text. Foundation's path standardisation drops a leading `/private`,
/// which would make a Project root differ from the working directory the system reports.
public struct GitProjectResolver: ProjectResolver {
  public init() {}

  public func project(for directory: String) -> Project {
    let start = normalized(directory)
    var current = start
    while true {
      if let root = repositoryRoot(at: current) {
        return Project(root: root)
      }
      guard let parent = parent(of: current) else { break }
      current = parent
    }
    return Project(root: start)
  }

  /// The Project root when `directory` holds a `.git` entry, otherwise nil.
  private func repositoryRoot(at directory: String) -> String? {
    let entry = directory == "/" ? "/.git" : directory + "/.git"
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: entry, isDirectory: &isDirectory) else {
      return nil
    }
    if isDirectory.boolValue {
      return directory
    }
    return mainRepository(ofWorktreePointer: entry, in: directory) ?? directory
  }

  /// A worktree's `.git` is a file pointing into `<main>/.git/worktrees/<name>`.
  private func mainRepository(ofWorktreePointer file: String, in directory: String) -> String? {
    guard let text = try? String(contentsOfFile: file, encoding: .utf8),
      let line = text.split(separator: "\n").first(where: { $0.hasPrefix("gitdir:") })
    else { return nil }
    let target = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
    let resolved = normalized(target.hasPrefix("/") ? target : directory + "/" + target)
    guard let marker = resolved.range(of: "/.git/worktrees/") else { return nil }
    return String(resolved[..<marker.lowerBound])
  }

  private func parent(of path: String) -> String? {
    guard path != "/", let slash = path.lastIndex(of: "/") else { return nil }
    let parent = String(path[..<slash])
    return parent.isEmpty ? "/" : parent
  }

  /// Resolves `.` and `..` and removes repeated or trailing slashes, without touching the disk.
  private func normalized(_ path: String) -> String {
    var components: [Substring] = []
    for component in path.split(separator: "/") {
      switch component {
      case ".": continue
      case "..": _ = components.popLast()
      default: components.append(component)
      }
    }
    return "/" + components.joined(separator: "/")
  }
}
