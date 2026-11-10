import Foundation

/// A scratch directory that exists for the life of one test suite instance.
final class TemporaryDirectory {
  let url: URL

  init() throws {
    let base = FileManager.default.temporaryDirectory
      .appendingPathComponent("aam-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    // The system reports working directories with symbolic links resolved, which
    // `resolvingSymlinksInPath` does not do for the temporary directory.
    guard let resolved = realpath(base.path, nil) else { throw CocoaError(.fileNoSuchFile) }
    defer { free(resolved) }
    url = URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
  }

  deinit {
    try? FileManager.default.removeItem(at: url)
  }

  @discardableResult
  func directory(_ path: String) throws -> URL {
    let target = url.appendingPathComponent(path, isDirectory: true)
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    return target
  }

  @discardableResult
  func file(_ path: String, _ contents: String) throws -> URL {
    let target = url.appendingPathComponent(path)
    try FileManager.default.createDirectory(
      at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(contents.utf8).write(to: target)
    return target
  }
}
