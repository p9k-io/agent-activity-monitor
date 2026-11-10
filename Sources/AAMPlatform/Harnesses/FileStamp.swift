import Darwin

/// The size and modification time of a file: enough to tell whether it has to be read again.
struct FileStamp: Sendable, Equatable {
  let size: Int64
  let modifiedSeconds: Int
  let modifiedNanoseconds: Int

  /// Nil when there is no such file.
  init?(path: String) {
    var info = stat()
    guard stat(path, &info) == 0 else { return nil }
    size = info.st_size
    modifiedSeconds = info.st_mtimespec.tv_sec
    modifiedNanoseconds = info.st_mtimespec.tv_nsec
  }
}
