/// What a process is there for, as far as its name and arguments tell.
public enum ProcessKind: String, Sendable, Codable, CaseIterable {
  /// The root process of a Session.
  case harness
  case mcpServer
  /// A development server or a watcher: something that keeps running and waits.
  case devServer
  case languageServer
  case testRunner
  /// A browser's renderer, GPU or network helper.
  case browserContent
  case simulator
  case virtualMachine
  case other
}

/// Tells the kind of a process from a list of rules. The first rule that matches wins.
public struct ProcessClassifier: Sendable {
  /// One way to recognise a kind. A rule matches when any of its conditions holds.
  public struct Rule: Sendable {
    public var kind: ProcessKind
    /// The executable, or the script an interpreter or a package runner was asked to run.
    public var programs: Set<String> = []
    public var pathContains: [String] = []
    public var namePrefixes: [String] = []
    public var nameContains: [String] = []
    /// A whole word in the executable name or in the name of the script being run.
    public var words: [String] = []
    /// Any text in the executable name or in the name of the script being run.
    public var textContains: [String] = []
    /// An argument after the program.
    public var arguments: Set<String> = []
    public var argumentPrefixes: [String] = []
    /// When not empty, `arguments` and `argumentPrefixes` count only for these programs.
    public var argumentsRequireProgram: Set<String> = []

    public init(_ kind: ProcessKind) {
      self.kind = kind
    }
  }

  public let rules: [Rule]

  public init(rules: [Rule]) {
    self.rules = rules
  }

  public func kind(of process: ProcessRecord) -> ProcessKind {
    let subject = Subject(process)
    return rules.first { subject.matches($0) }?.kind ?? .other
  }
}

/// A process seen the way the rules look at it.
private struct Subject {
  let path: String
  let name: String
  /// The executable and every script it was asked to run, without extensions and versions.
  var programs: Set<String>
  /// The executable name and the script names as they were written.
  var texts: [String]
  /// The arguments after the last program.
  var trailing: ArraySlice<String>

  private static let interpreters: Set<String> = [
    "node", "bun", "deno", "python", "python3", "ruby", "tsx", "ts-node", "sh", "bash", "zsh",
  ]
  private static let runners: Set<String> = ["npm", "npx", "pnpm", "yarn", "bunx", "uv", "uvx"]
  private static let runnerVerbs: Set<String> = ["exec", "run", "dlx", "x", "tool"]
  private static let extensions = [".mjs", ".cjs", ".mts", ".js", ".ts", ".py", ".sh", ".rb"]

  init(_ process: ProcessRecord) {
    path = process.executablePath
    name = process.name
    programs = [process.name.lowercased()]
    texts = [process.name.lowercased()]
    trailing = process.arguments.dropFirst()

    var head = process.arguments.first.map(Self.program) ?? process.name.lowercased()
    programs.insert(head)
    // An interpreter runs a script, and a package runner runs a program that may be one again.
    for _ in 0..<3 where Self.interpreters.contains(head) || Self.runners.contains(head) {
      guard let index = scriptIndex(after: head) else { break }
      let script = trailing[index]
      texts.append(script.lowercased())
      head = Self.program(script)
      programs.insert(head)
      trailing = trailing[(index + 1)...]
    }
  }

  /// Where the script or program name sits among the remaining arguments.
  private func scriptIndex(after head: String) -> Int? {
    if head.hasPrefix("python"), let module = trailing.firstIndex(of: "-m"),
      trailing.indices.contains(module + 1)
    {
      return module + 1
    }
    return trailing.firstIndex { argument in
      !argument.hasPrefix("-")
        && !(Self.runners.contains(head) && Self.runnerVerbs.contains(argument))
    }
  }

  /// The name of a program as the rules know it: last path component, no version, no extension.
  private static func program(_ text: String) -> String {
    var name = text.split(separator: "/").last.map(String.init) ?? text
    if let version = name.dropFirst().firstIndex(of: "@") {
      name = String(name[..<version])
    }
    for suffix in extensions where name.hasSuffix(suffix) {
      name = String(name.dropLast(suffix.count))
      break
    }
    return name.lowercased()
  }

  func matches(_ rule: ProcessClassifier.Rule) -> Bool {
    if !rule.programs.isDisjoint(with: programs) { return true }
    if rule.pathContains.contains(where: path.contains) { return true }
    if rule.namePrefixes.contains(where: name.hasPrefix) { return true }
    if rule.nameContains.contains(where: name.contains) { return true }
    if rule.textContains.contains(where: { text in texts.contains { $0.contains(text) } }) {
      return true
    }
    if rule.words.contains(where: { word in texts.contains { Self.contains(word: word, in: $0) } })
    {
      return true
    }
    let allowed =
      rule.argumentsRequireProgram.isEmpty
      || !rule.argumentsRequireProgram.isDisjoint(with: programs)
    guard allowed else { return false }
    return trailing.contains { argument in
      rule.arguments.contains(argument) || rule.argumentPrefixes.contains(where: argument.hasPrefix)
    }
  }

  /// Whether `word` occurs in `text` with no letter or digit right before or after it.
  private static func contains(word: String, in text: String) -> Bool {
    var search = text[...]
    while let range = search.range(of: word) {
      let before =
        range.lowerBound > text.startIndex ? text[text.index(before: range.lowerBound)] : nil
      let after = range.upperBound < text.endIndex ? text[range.upperBound] : nil
      if !isWordCharacter(before), !isWordCharacter(after) { return true }
      search = search[range.upperBound...]
    }
    return false
  }

  private static func isWordCharacter(_ character: Character?) -> Bool {
    guard let character else { return false }
    return character.isLetter || character.isNumber
  }
}

extension ProcessClassifier {
  /// The rules shipped with the app. To teach it a new tool, add to the lists here.
  public static let standard = ProcessClassifier(rules: [
    rule(.simulator) {
      $0.pathContains = ["/CoreSimulator/"]
      $0.programs = ["launchd_sim"]
    },
    rule(.browserContent) {
      $0.namePrefixes = ["com.apple.WebKit."]
      $0.nameContains = ["Helper (Renderer)", "Helper (GPU)"]
      $0.programs = ["chrome-headless-shell"]
      $0.argumentPrefixes = ["--type=renderer", "--type=gpu-process"]
    },
    rule(.virtualMachine) {
      $0.programs = ["com.apple.virtualization.virtualmachine", "vfkit", "qemu-system-aarch64"]
    },
    rule(.mcpServer) {
      $0.words = ["mcp"]
      $0.textContains = ["modelcontextprotocol"]
    },
    rule(.languageServer) {
      $0.programs = [
        "tsserver", "typescript-language-server", "rust-analyzer", "gopls", "sourcekit-lsp",
        "pyright-langserver", "eslint_d", "vscode-eslint-language-server", "lua-language-server",
      ]
      $0.arguments = ["__run_server", "lsp-proxy"]
    },
    rule(.testRunner) {
      $0.programs = ["vitest", "jest", "mocha", "pytest", "xctest", "playwright"]
    },
    rule(.devServer) {
      // `dev` is a script of that name, as in `pnpm dev` or `node scripts/dev.mjs`.
      $0.programs = [
        "dev", "vite", "nodemon", "webpack-dev-server", "http-server", "live-server",
        "browser-sync", "uvicorn", "gunicorn", "metro",
      ]
    },
    rule(.devServer) {
      $0.arguments = ["dev", "serve", "preview"]
      $0.argumentsRequireProgram = [
        "next", "nuxt", "astro", "storybook", "wrangler", "turbo", "remix", "expo", "docusaurus",
        "rails", "flask",
      ]
    },
    rule(.devServer) {
      $0.arguments = ["--watch", "-w", "watch", "--reload"]
      $0.argumentPrefixes = ["--watch="]
    },
  ])

  private static func rule(_ kind: ProcessKind, _ configure: (inout Rule) -> Void) -> Rule {
    var rule = Rule(kind)
    configure(&rule)
    return rule
  }
}
