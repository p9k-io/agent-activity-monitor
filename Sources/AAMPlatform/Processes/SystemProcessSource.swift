import AAMCore
import Foundation

/// Every process on the machine: the current user's in full detail through libproc, everyone
/// else's through `ps`.
public struct SystemProcessSource: ProcessSource {
  private let own: LibprocProcessSource
  private let includesOtherUsers: Bool

  /// - Parameter includesOtherUsers: Running `ps` costs more than reading libproc. A caller that
  ///   samples often can leave other users' processes out of most samples.
  public init(markerNames: Set<String>, includesOtherUsers: Bool = true) {
    own = LibprocProcessSource(markerNames: markerNames)
    self.includesOtherUsers = includesOtherUsers
  }

  public func snapshot() -> Snapshot {
    let takenAt = Date()
    let mine = own.processes()
    guard includesOtherUsers else {
      return Snapshot(takenAt: takenAt, processes: mine)
    }
    let known = Set(mine.map(\.pid))
    let others = PsRunner.processes().filter { !known.contains($0.pid) }
    return Snapshot(takenAt: takenAt, processes: mine + others)
  }

  /// The current user's process with this identifier right now.
  public func record(for pid: Int32) -> ProcessRecord? {
    own.record(for: pid)
  }
}

/// Runs `/bin/ps`, which is setuid root and therefore sees every process.
enum PsRunner {
  static func processes() -> [ProcessRecord] {
    let ps = Process()
    ps.executableURL = URL(fileURLWithPath: "/bin/ps")
    ps.arguments = ["-axo", PsOutput.columns]
    // Month names and number formats must not depend on the user's locale.
    ps.environment = ["LC_ALL": "C"]
    let output = Pipe()
    ps.standardOutput = output
    ps.standardError = FileHandle.nullDevice
    do {
      try ps.run()
    } catch {
      return []
    }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    ps.waitUntilExit()
    return PsOutput.parse(String(decoding: data, as: UTF8.self))
  }
}
