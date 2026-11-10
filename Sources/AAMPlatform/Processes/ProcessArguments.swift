/// The executable path, the arguments and the marked environment variables of a process, read
/// from the buffer `sysctl KERN_PROCARGS2` returns.
///
/// Every other environment variable is skipped without being kept: an environment holds secrets.
public struct ProcessArguments: Sendable, Equatable {
  public let executablePath: String
  public let arguments: [String]
  public let markers: [String: String]

  /// Layout: the argument count, the executable path, padding, the arguments, the environment.
  public static func parse(_ bytes: [UInt8], markerNames: Set<String>) -> ProcessArguments? {
    let countSize = MemoryLayout<Int32>.size
    guard bytes.count >= countSize else { return nil }
    let count = bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
    guard count >= 0 else { return nil }

    var reader = Reader(bytes: bytes, position: countSize)
    guard let path = reader.string() else { return nil }
    reader.skipPadding()

    var arguments: [String] = []
    while arguments.count < Int(count), let argument = reader.string() {
      arguments.append(argument)
    }

    var markers: [String: String] = [:]
    if arguments.count == Int(count), !markerNames.isEmpty {
      while let entry = reader.string(), !entry.isEmpty {
        guard let separator = entry.firstIndex(of: "=") else { continue }
        let name = String(entry[..<separator])
        if markerNames.contains(name) {
          markers[name] = String(entry[entry.index(after: separator)...])
        }
      }
    }
    return ProcessArguments(executablePath: path, arguments: arguments, markers: markers)
  }
}

private struct Reader {
  let bytes: [UInt8]
  var position: Int

  /// The next NUL-terminated string, or nil when the buffer ends before its terminator.
  mutating func string() -> String? {
    guard position < bytes.count,
      let end = bytes[position...].firstIndex(of: 0)
    else { return nil }
    defer { position = end + 1 }
    return String(decoding: bytes[position..<end], as: UTF8.self)
  }

  mutating func skipPadding() {
    while position < bytes.count, bytes[position] == 0 {
      position += 1
    }
  }
}
