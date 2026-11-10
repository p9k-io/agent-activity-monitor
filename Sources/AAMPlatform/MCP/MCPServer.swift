import Foundation

/// A tool a Model Context Protocol client can call.
public struct MCPTool: Sendable {
  public let name: String
  public let description: String
  /// The JSON Schema of the arguments.
  public let inputSchema: JSONValue
  /// Does the work and returns what the client is told, as text. An error it throws is told
  /// to the client as the outcome of the call.
  public let call: @Sendable (JSONValue) throws -> String

  public init(
    name: String, description: String, inputSchema: JSONValue,
    call: @escaping @Sendable (JSONValue) throws -> String
  ) {
    self.name = name
    self.description = description
    self.inputSchema = inputSchema
    self.call = call
  }
}

/// Answers Model Context Protocol requests that arrive one JSON-RPC message per line.
///
/// It offers tools and nothing else: no resources, no prompts, no requests of its own.
public struct MCPServer: Sendable {
  /// The protocol versions this server speaks, the latest first.
  public static let protocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

  private let name: String
  private let version: String
  private let instructions: String?
  private let tools: [MCPTool]

  public init(name: String, version: String, instructions: String? = nil, tools: [MCPTool]) {
    self.name = name
    self.version = version
    self.instructions = instructions
    self.tools = tools
  }

  /// Reads messages from `input` until it ends, and writes each reply as one line to `output`.
  public func run(
    input: FileHandle = .standardInput, output: FileHandle = .standardOutput
  ) {
    var pending = Data()
    while true {
      let chunk = input.availableData
      if chunk.isEmpty { break }
      pending.append(chunk)
      while let end = pending.firstIndex(of: UInt8(ascii: "\n")) {
        let line = pending[pending.startIndex..<end]
        pending = Data(pending[pending.index(after: end)...])
        guard line.contains(where: { $0 != UInt8(ascii: " ") && $0 != UInt8(ascii: "\r") }),
          var reply = reply(to: Data(line))
        else { continue }
        reply.append(UInt8(ascii: "\n"))
        output.write(reply)
      }
    }
  }

  /// The reply to one message, or nil when the message needs none.
  public func reply(to line: Data) -> Data? {
    guard let message = try? JSONDecoder().decode(JSONValue.self, from: line) else {
      return encode(failure(-32700, "The message is not JSON.", id: .null))
    }
    guard case .object = message, let method = message["method"]?.string else {
      return encode(failure(-32600, "The message is not a request.", id: message["id"] ?? .null))
    }
    // A message without an identifier is a notification: nothing is sent back.
    guard let id = message["id"] else { return nil }
    return encode(answer(method, message["params"] ?? .object([:]), id: id))
  }

  private func answer(_ method: String, _ params: JSONValue, id: JSONValue) -> JSONValue {
    switch method {
    case "initialize":
      let asked = params["protocolVersion"]?.string
      var result: [String: JSONValue] = [
        "protocolVersion": .string(
          asked.flatMap { Self.protocolVersions.contains($0) ? $0 : nil }
            ?? Self.protocolVersions[0]),
        "capabilities": .object(["tools": .object([:])]),
        "serverInfo": .object(["name": .string(name), "version": .string(version)]),
      ]
      if let instructions { result["instructions"] = .string(instructions) }
      return success(.object(result), id: id)
    case "ping":
      return success(.object([:]), id: id)
    case "tools/list":
      let listed = tools.map { tool in
        JSONValue.object([
          "name": .string(tool.name), "description": .string(tool.description),
          "inputSchema": tool.inputSchema,
        ])
      }
      return success(.object(["tools": .array(listed)]), id: id)
    case "tools/call":
      guard let name = params["name"]?.string, let tool = tools.first(where: { $0.name == name })
      else {
        return failure(-32602, "There is no such tool.", id: id)
      }
      return success(outcome(of: tool, with: params["arguments"] ?? .object([:])), id: id)
    default:
      return failure(-32601, "The method \(method) is not offered.", id: id)
    }
  }

  private func outcome(of tool: MCPTool, with arguments: JSONValue) -> JSONValue {
    let text: String
    let failed: Bool
    do {
      text = try tool.call(arguments)
      failed = false
    } catch {
      text = String(describing: error)
      failed = true
    }
    return .object([
      "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
      "isError": .bool(failed),
    ])
  }

  private func success(_ result: JSONValue, id: JSONValue) -> JSONValue {
    .object(["jsonrpc": .string("2.0"), "id": id, "result": result])
  }

  private func failure(_ code: Int64, _ message: String, id: JSONValue) -> JSONValue {
    .object([
      "jsonrpc": .string("2.0"), "id": id,
      "error": .object(["code": .integer(code), "message": .string(message)]),
    ])
  }

  private func encode(_ value: JSONValue) -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    // A value made only of JSON values always encodes.
    return (try? encoder.encode(value)) ?? Data("{}".utf8)
  }
}
