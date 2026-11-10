import AAMPlatform
import Foundation
import Testing

struct MCPServerTests {
  struct Refused: Error, CustomStringConvertible {
    let description = "that cannot be done"
  }

  let server = MCPServer(
    name: "test-server", version: "1.2.3", instructions: "Read before you ask.",
    tools: [
      MCPTool(
        name: "echo", description: "Says back what it was given.",
        inputSchema: .object(["type": .string("object")])
      ) { arguments in
        "said: \(arguments["text"]?.string ?? "nothing")"
      },
      MCPTool(
        name: "refuse", description: "Always fails.",
        inputSchema: .object(["type": .string("object")])
      ) { _ in
        throw Refused()
      },
    ])

  /// Sends one message and reads the reply as JSON.
  func reply(_ message: String) throws -> JSONValue {
    let data = try #require(server.reply(to: Data(message.utf8)))
    #expect(!data.contains(UInt8(ascii: "\n")))
    return try JSONDecoder().decode(JSONValue.self, from: data)
  }

  @Test func `initialize answers with the version the client asked for and says who it is`()
    throws
  {
    let reply = try reply(
      """
      {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26",\
      "capabilities":{},"clientInfo":{"name":"client","version":"0"}}}
      """)

    let result = try #require(reply["result"])
    #expect(reply["jsonrpc"] == .string("2.0"))
    #expect(reply["id"] == .integer(1))
    #expect(result["protocolVersion"] == .string("2025-03-26"))
    #expect(result["serverInfo"]?["name"] == .string("test-server"))
    #expect(result["serverInfo"]?["version"] == .string("1.2.3"))
    #expect(result["capabilities"]?["tools"] != nil)
    #expect(result["instructions"] == .string("Read before you ask."))
  }

  @Test func `a version the server does not know is answered with the latest it does`() throws {
    let reply = try reply(
      """
      {"jsonrpc":"2.0","id":"a","method":"initialize","params":{"protocolVersion":"1999-01-01"}}
      """)

    #expect(reply["id"] == .string("a"))
    #expect(reply["result"]?["protocolVersion"] == .string(MCPServer.protocolVersions[0]))
  }

  @Test func `a notification gets no reply`() {
    let line = Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8)

    #expect(server.reply(to: line) == nil)
  }

  @Test func `a ping is answered with an empty result`() throws {
    let reply = try reply(#"{"jsonrpc":"2.0","id":7,"method":"ping"}"#)

    #expect(reply["result"] == .object([:]))
  }

  @Test func `the tools are listed with what they are for and what they take`() throws {
    let reply = try reply(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)

    let tools = try #require(reply["result"]?["tools"]?.array)
    #expect(tools.map { $0["name"] } == [.string("echo"), .string("refuse")])
    #expect(tools[0]["description"] == .string("Says back what it was given."))
    #expect(tools[0]["inputSchema"]?["type"] == .string("object"))
  }

  @Test func `calling a tool hands it the arguments and returns what it says as text`() throws {
    let reply = try reply(
      """
      {"jsonrpc":"2.0","id":3,"method":"tools/call",\
      "params":{"name":"echo","arguments":{"text":"hello"}}}
      """)

    let result = try #require(reply["result"])
    #expect(result["isError"] == .bool(false))
    #expect(result["content"]?.array?.first?["type"] == .string("text"))
    #expect(result["content"]?.array?.first?["text"] == .string("said: hello"))
  }

  @Test func `a tool called without arguments gets an empty object`() throws {
    let reply = try reply(
      #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"echo"}}"#)

    #expect(reply["result"]?["content"]?.array?.first?["text"] == .string("said: nothing"))
  }

  @Test func `a tool that fails is reported as the result of the call, not as a broken call`()
    throws
  {
    let reply = try reply(
      #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"refuse"}}"#)

    #expect(reply["error"] == nil)
    #expect(reply["result"]?["isError"] == .bool(true))
    #expect(
      reply["result"]?["content"]?.array?.first?["text"] == .string("that cannot be done"))
  }

  @Test(arguments: [
    (#"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"nope"}}"#, -32602),
    (#"{"jsonrpc":"2.0","id":5,"method":"tools/call"}"#, -32602),
    (#"{"jsonrpc":"2.0","id":5,"method":"resources/list"}"#, -32601),
    (#"{"jsonrpc":"2.0","id":5}"#, -32600),
    (#"[1, 2]"#, -32600),
    (#"this is not JSON"#, -32700),
  ])
  func `what cannot be answered gets the error code that says why`(message: String, code: Int64)
    throws
  {
    let reply = try reply(message)

    #expect(reply["result"] == nil)
    #expect(reply["error"]?["code"] == .integer(code))
    #expect(reply["error"]?["message"]?.string?.isEmpty == false)
  }

  @Test func `a message that could not be read is answered without an identifier`() throws {
    let reply = try reply("{")

    #expect(reply["id"] == .null)
  }
}

struct JSONValueTests {
  @Test func `every kind of JSON value survives a round trip`() throws {
    let text = #"{"a":[1,2.5,"x",true,null],"b":{"c":-3}}"#

    let value = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys

    #expect(
      value
        == .object([
          "a": .array([.integer(1), .number(2.5), .string("x"), .bool(true), .null]),
          "b": .object(["c": .integer(-3)]),
        ]))
    #expect(String(decoding: try encoder.encode(value), as: UTF8.self) == text)
  }

  @Test func `a value is read by key, and asking the wrong kind gives nothing`() {
    let value = JSONValue.object(["n": .integer(4), "s": .string("x"), "l": .array([.null])])

    #expect(value["n"]?.integer == 4)
    #expect(value["s"]?.string == "x")
    #expect(value["l"]?.array == [.null])
    #expect(value["missing"] == nil)
    #expect(value["n"]?.string == nil)
    #expect(JSONValue.string("x")["n"] == nil)
  }
}
