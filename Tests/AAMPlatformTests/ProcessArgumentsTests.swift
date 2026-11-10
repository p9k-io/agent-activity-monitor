import AAMPlatform
import Testing

struct ProcessArgumentsTests {
  /// Builds a buffer in the layout `sysctl KERN_PROCARGS2` returns: the argument count, the
  /// executable path, padding, the arguments, then the environment.
  func buffer(
    path: String,
    arguments: [String],
    environment: [String],
    padding: Int = 3
  ) -> [UInt8] {
    var bytes = withUnsafeBytes(of: Int32(arguments.count)) { Array($0) }
    bytes += Array(path.utf8) + [UInt8](repeating: 0, count: 1 + padding)
    for string in arguments + environment {
      bytes += Array(string.utf8) + [0]
    }
    bytes += [0]
    return bytes
  }

  @Test func `the executable path and the arguments are read`() throws {
    let bytes = buffer(
      path: "/opt/bin/node", arguments: ["node", "server.js", "--port", "3000"], environment: [])

    let parsed = try #require(ProcessArguments.parse(bytes, markerNames: []))

    #expect(parsed.executablePath == "/opt/bin/node")
    #expect(parsed.arguments == ["node", "server.js", "--port", "3000"])
  }

  @Test func `only environment variables on the marker list are kept`() throws {
    let bytes = buffer(
      path: "/opt/bin/node",
      arguments: ["node"],
      environment: ["HOME=/Users/someone", "SESSION_ID=abc", "API_TOKEN=do-not-read"])

    let parsed = try #require(ProcessArguments.parse(bytes, markerNames: ["SESSION_ID"]))

    #expect(parsed.markers == ["SESSION_ID": "abc"])
  }

  @Test func `an empty argument does not shift the ones after it`() throws {
    let bytes = buffer(
      path: "/bin/tool", arguments: ["tool", "", "last"], environment: ["SESSION_ID=abc"])

    let parsed = try #require(ProcessArguments.parse(bytes, markerNames: ["SESSION_ID"]))

    #expect(parsed.arguments == ["tool", "", "last"])
    #expect(parsed.markers == ["SESSION_ID": "abc"])
  }

  @Test func `a marker value may itself contain an equals sign`() throws {
    let bytes = buffer(path: "/bin/tool", arguments: ["tool"], environment: ["SESSION_ID=a=b"])

    let parsed = try #require(ProcessArguments.parse(bytes, markerNames: ["SESSION_ID"]))

    #expect(parsed.markers == ["SESSION_ID": "a=b"])
  }

  @Test func `a buffer too short to hold the argument count is rejected`() {
    #expect(ProcessArguments.parse([1, 0], markerNames: []) == nil)
  }

  @Test func `a truncated buffer yields the arguments that are complete`() throws {
    var bytes = buffer(path: "/bin/tool", arguments: ["tool", "one", "two"], environment: [])
    // Cuts the final terminator and the whole of "two" with its terminator.
    bytes.removeLast(5)

    let parsed = try #require(ProcessArguments.parse(bytes, markerNames: []))

    #expect(parsed.arguments == ["tool", "one"])
  }
}
