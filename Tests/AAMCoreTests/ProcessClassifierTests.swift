import AAMCore
import Testing

struct ProcessClassifierTests {
  let classifier = ProcessClassifier.standard

  @Test(arguments: [
    // MCP servers
    ("/opt/bin/node", ["node", "/work/node_modules/.bin/playwright-mcp"], ProcessKind.mcpServer),
    ("/opt/bin/node", ["npm", "exec", "@playwright/mcp@latest"], .mcpServer),
    ("/opt/bin/node", ["npm", "exec", "chrome-devtools-mcp@latest"], .mcpServer),
    ("/opt/bin/mcp-server-darwin-arm64", ["mcp-server-darwin-arm64"], .mcpServer),
    ("/opt/bin/node", ["npm", "exec", "@modelcontextprotocol/server-memory"], .mcpServer),
    // Dev servers and watchers
    ("/opt/bin/node", ["node", "/work/node_modules/.bin/next", "dev"], .devServer),
    ("/opt/bin/node", ["node", "/work/node_modules/.bin/vite"], .devServer),
    ("/opt/bin/node", ["node", "scripts/dev.mjs", "some-argument"], .devServer),
    ("/opt/bin/node", ["pnpm", "dev"], .devServer),
    ("/opt/bin/node", ["node", "/work/node_modules/.bin/tsc", "--watch"], .devServer),
    ("/opt/bin/python3", ["python3", "-m", "uvicorn", "app:main", "--reload"], .devServer),
    // Language servers
    ("/work/node_modules/@biomejs/cli/biome", ["biome", "__run_server"], .languageServer),
    ("/opt/bin/node", ["node", "/work/node_modules/typescript/lib/tsserver.js"], .languageServer),
    ("/opt/bin/rust-analyzer", ["rust-analyzer"], .languageServer),
    // Test runners win over the watch flag
    ("/opt/bin/node", ["node", "/work/node_modules/.bin/vitest", "--watch"], .testRunner),
    ("/opt/bin/python3", ["python3", "-m", "pytest", "-q"], .testRunner),
    // Things that run outside a Session tree
    (
      "/System/Library/Frameworks/WebKit.framework/XPCServices/"
        + "com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent",
      ["com.apple.WebKit.WebContent"], .browserContent
    ),
    (
      "/Applications/Browser.app/Contents/Frameworks/Browser Helper (Renderer).app/Contents/MacOS/"
        + "Browser Helper (Renderer)", ["Browser Helper (Renderer)", "--type=renderer"],
      .browserContent
    ),
    ("/Library/Developer/CoreSimulator/Volumes/x/usr/libexec/backboardd", [], .simulator),
    (
      "/usr/libexec/launchd_sim", ["launchd_sim", "/tmp/devices/ABCD/launchd_bootstrap"], .simulator
    ),
    (
      "/System/Library/Frameworks/Virtualization.framework/XPCServices/"
        + "com.apple.Virtualization.VirtualMachine.xpc/Contents/MacOS/"
        + "com.apple.Virtualization.VirtualMachine", [], .virtualMachine
    ),
    // Everything else
    ("/bin/zsh", ["zsh", "-c", "echo done"], .other),
    ("/opt/bin/node", ["node", "build.js"], .other),
    ("/opt/bin/node", ["node", "/work/node_modules/.bin/next", "build"], .other),
  ])
  func `a process is classified by its name and arguments`(
    path: String, arguments: [String], expected: ProcessKind
  ) {
    let process = ProcessRecord.make(1, path: path, arguments: arguments)

    #expect(classifier.kind(of: process) == expected)
  }

  @Test func `a word that merely contains mcp is not an MCP server`() {
    let process = ProcessRecord.make(1, path: "/opt/bin/node", arguments: ["node", "tcmcpx.js"])

    #expect(classifier.kind(of: process) == .other)
  }
}
