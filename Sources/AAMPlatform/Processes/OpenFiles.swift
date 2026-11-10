import Darwin

/// Tells which files a process holds open.
public protocol OpenFileListing: Sendable {
  /// Paths of the files a process of the current user holds open. Empty when the process is gone
  /// or belongs to someone else.
  func openFiles(of pid: Int32) -> [String]
}

/// Lists open files through libproc.
public struct LibprocOpenFiles: OpenFileListing {
  public init() {}

  public func openFiles(of pid: Int32) -> [String] {
    let needed = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
    guard needed > 0 else { return [] }
    let stride = MemoryLayout<proc_fdinfo>.stride
    // Room for descriptors opened between the two calls.
    var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(needed) / stride + 16)
    let used = descriptors.withUnsafeMutableBytes {
      proc_pidinfo(pid, PROC_PIDLISTFDS, 0, $0.baseAddress, Int32($0.count))
    }
    guard used > 0 else { return [] }

    var paths: [String] = []
    for descriptor in descriptors.prefix(Int(used) / stride)
    where descriptor.proc_fdtype == UInt32(PROX_FDTYPE_VNODE) {
      var info = vnode_fdinfowithpath()
      let size = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
      guard
        proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDVNODEPATHINFO, &info, size) == size
      else { continue }
      let path = withUnsafeBytes(of: info.pvip.vip_path) {
        String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
      }
      if !path.isEmpty {
        paths.append(path)
      }
    }
    return paths
  }
}
