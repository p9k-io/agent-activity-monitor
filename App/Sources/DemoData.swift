#if DEBUG
  import AAMCore
  import AAMPlatform
  import Foundation

  /// Made-up Sessions and processes, for looking at the app without showing or touching
  /// anything real: start a debug build with `-demo YES`.
  ///
  /// Every process identifier here is above the highest one macOS gives out, so none of them
  /// can name a real process, and a Cleanup confirmed in this mode finds nothing to end.
  enum DemoData {
    /// One made-up process.
    private struct Row {
      let pid: Int32
      var parent: Int32 = 1
      let path: String
      var arguments: [String] = []
      let megabytes: UInt64
      /// How long ago it started.
      let hours: Double
      /// CPU use in percent of one core.
      var cpu: Double = 0
      var user = getuid()
      var terminal = false
    }

    private static let storefront = "/Users/demo/work/storefront"
    private static let api = "/Users/demo/work/api"
    private static let node = "/opt/bin/node"
    private static let filesServer = ["node", "/opt/tools/files-mcp/server.js"]
    private static let simulator = "/Library/Developer/CoreSimulator/Runtime/"
    private static let webContent =
      "/System/Library/Frameworks/WebKit.framework/XPCServices/"
      + "com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent"
    private static let virtualMachine =
      "/System/Library/Frameworks/Virtualization.framework/XPCServices/"
      + "com.apple.Virtualization.VirtualMachine"

    private static let rows: [Row] = [
      // A working Session with a test run, a dev server and a server that was started twice.
      Row(pid: 100_100, path: "/opt/bin/claude", megabytes: 410, hours: 3, cpu: 12, terminal: true),
      Row(
        pid: 100_101, parent: 100_100, path: node, arguments: filesServer, megabytes: 64, hours: 1),
      Row(
        pid: 100_105, parent: 100_100, path: node, arguments: filesServer, megabytes: 61, hours: 3),
      Row(
        pid: 100_102, parent: 100_100, path: node, arguments: ["node", "node_modules/.bin/vite"],
        megabytes: 220, hours: 2, cpu: 3),
      Row(pid: 100_103, parent: 100_102, path: "/opt/bin/esbuild", megabytes: 38, hours: 2, cpu: 1),
      Row(
        pid: 100_104, parent: 100_100, path: node, arguments: ["node", "node_modules/.bin/vitest"],
        megabytes: 510, hours: 0.2, cpu: 184),
      // A Session nobody has touched for two days.
      Row(pid: 100_200, path: "/opt/bin/codex", megabytes: 360, hours: 60, terminal: true),
      Row(
        pid: 100_201, parent: 100_200, path: node, arguments: filesServer, megabytes: 58, hours: 60),
      // A Session that has been waiting for an answer since yesterday.
      Row(pid: 100_300, path: "/opt/bin/claude", megabytes: 395, hours: 30, terminal: true),
      Row(
        pid: 100_301, parent: 100_300, path: node,
        arguments: ["node", "/opt/tools/search-mcp/server.js"], megabytes: 71, hours: 30),
      // Left behind by a Session that ended.
      Row(
        pid: 100_400, path: node, arguments: ["node", "scripts/dev.mjs"], megabytes: 180, hours: 9),
      Row(pid: 100_401, path: "/opt/bin/redis-server", megabytes: 24, hours: 9),
      // Induced load, and something that has nothing to do with any Session.
      Row(pid: 100_500, path: "/usr/libexec/launchd_sim", megabytes: 12, hours: 5, cpu: 2),
      Row(
        pid: 100_501, parent: 100_500, path: simulator + "backboardd", megabytes: 150, hours: 5,
        cpu: 96),
      Row(
        pid: 100_502, parent: 100_500, path: simulator + "SpringBoard", megabytes: 420, hours: 5,
        cpu: 212),
      Row(pid: 100_600, path: webContent, megabytes: 310, hours: 11, cpu: 99),
      Row(pid: 100_601, path: webContent, megabytes: 290, hours: 11, cpu: 98),
      Row(pid: 100_602, path: webContent, megabytes: 120, hours: 2, cpu: 41),
      Row(pid: 100_700, path: virtualMachine, megabytes: 2100, hours: 20, cpu: 58),
      Row(
        pid: 100_800, path: "/System/Library/Frameworks/CoreServices.framework/mds_stores",
        megabytes: 240, hours: 90, cpu: 131, user: 0),
    ]

    static func sample(now: Date = Date()) -> Sample {
      let hour: TimeInterval = 3600
      let processes = rows.map { row in
        ProcessRecord(
          pid: row.pid, parentPID: row.parent, groupID: row.pid, userID: row.user,
          startedAt: now - row.hours * hour, executablePath: row.path, arguments: row.arguments,
          workingDirectory: nil, cpuTime: .zero, residentBytes: row.megabytes * 1_048_576,
          isZombie: false, hasTerminal: row.terminal, markers: [:])
      }
      let keyOf = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0.key) })
      func keys(_ pids: Int32...) -> [ProcessRecord.Key] { pids.compactMap { keyOf[$0] } }
      func session(
        _ value: String, _ harness: HarnessID, root: Int32, in project: String, _ title: String,
        _ state: SessionState, idleFor hours: Double
      ) -> Session? {
        keyOf[root].map { root in
          Session(
            id: SessionID(harness: harness, value: value), root: root,
            project: Project(root: project), workingDirectory: project, title: title, state: state,
            lastActivityAt: now - hours * hour,
            resumeCommand: harness == .codex ? "codex resume \(value)" : "claude --resume \(value)",
            markers: [:])
        }
      }
      let sessions = [
        session(
          "demo-checkout", .claudeCode, root: 100_100, in: storefront, "Checkout redesign",
          .working, idleFor: 0),
        session(
          "demo-flaky", .codex, root: 100_200, in: storefront, "Fix flaky tests", .idle,
          idleFor: 50),
        session(
          "demo-limiter", .claudeCode, root: 100_300, in: api, "Rate limiter", .waiting,
          idleFor: 26),
      ].compactMap(\.self)

      // What the app would remember: a Session that ended three hours ago and what it left.
      let ended = SessionID(harness: .claudeCode, value: "demo-ended")
      var memory = Memory.empty
      memory.sessions[ended] = Memory.PastSession(
        project: Project(root: api), title: "Import job", markers: [:],
        lastSeenAt: now - 3 * hour, endedAt: now - 3 * hour)
      for key in keys(100_400, 100_401) {
        memory.lineage[key] = Memory.Lineage(session: ended, project: Project(root: api))
        memory.lastBusyAt[key] = now - 5 * hour
      }
      memory.activityAsOf = now

      let load = [
        InducedLoad(
          id: "simulator:demo", kind: .simulator(device: "AAAAAAAA-1111-4222-8333-BBBBBBBBBBBB"),
          title: "iOS Simulator · Phone 99 Pro", processes: keys(100_500, 100_501, 100_502)),
        InducedLoad(
          id: "web-content:demo", kind: .webContent(application: "com.example.terminal"),
          title: "Web content of Example Terminal", processes: keys(100_600, 100_601, 100_602)),
        InducedLoad(
          id: "virtual-machine:demo", kind: .virtualMachine, title: "Virtual machine of Docker",
          processes: keys(100_700)),
      ]

      let snapshot = Snapshot(takenAt: now, processes: processes)
      let inventory = Attributor().inventory(of: snapshot, sessions: sessions, memory: memory)
      let usage = Usage(
        Dictionary(uniqueKeysWithValues: zip(processes, rows).map { ($0.key, $1.cpu) }))
      let culprits = CulpritRanker().culprits(in: inventory, usage: usage, inducedLoad: load)
      return Sample(
        observation: Reading(
          snapshot: snapshot, sessions: sessions, inventory: inventory,
          places: Dictionary(
            uniqueKeysWithValues: zip(
              sessions, ["Shop › checkout", "Shop › tests", "API › limiter"]
            )
            .map { session, location in
              (
                session.id,
                HostPlace(
                  host: "Example Terminal", hostPID: 100_900, location: location, reference: [:])
              )
            })),
        usage: usage,
        memory: memory,
        culprits: culprits.enumerated().map { index, culprit in
          TrackedCulprit(culprit: culprit, hotSince: now - TimeInterval(index + 1) * 1500)
        },
        inducedLoad: load,
        findings: StalenessRules().findings(in: inventory, memory: memory, now: now))
    }

    /// A made-up week of CPU time for the Sessions above.
    static let report: UsageReport = {
      let storefront = Project(root: DemoData.storefront)
      let api = Project(root: DemoData.api)
      let checkout = SessionID(harness: .claudeCode, value: "demo-checkout")
      let flaky = SessionID(harness: .codex, value: "demo-flaky")
      let limiter = SessionID(harness: .claudeCode, value: "demo-limiter")
      func total(_ project: Project, _ session: SessionID?, _ kind: ProcessKind, hours: Double)
        -> UsageTotal
      {
        UsageTotal(project: project, session: session, kind: kind, cpuSeconds: hours * 3600)
      }
      return UsageReport(
        totals: [
          total(storefront, checkout, .testRunner, hours: 9.4),
          total(storefront, checkout, .harness, hours: 2.1),
          total(storefront, checkout, .devServer, hours: 0.8),
          total(storefront, flaky, .testRunner, hours: 3.2),
          total(storefront, flaky, .harness, hours: 0.9),
          total(api, limiter, .harness, hours: 1.6),
          total(api, limiter, .mcpServer, hours: 0.3),
          total(api, nil, .devServer, hours: 0.7),
        ],
        peaks: [
          UsagePeak(project: storefront, session: checkout, residentBytes: 1_900 * 1_048_576),
          UsagePeak(project: storefront, session: flaky, residentBytes: 620 * 1_048_576),
          UsagePeak(project: api, session: limiter, residentBytes: 540 * 1_048_576),
          UsagePeak(project: api, session: nil, residentBytes: 210 * 1_048_576),
        ],
        titles: [checkout: "Checkout redesign", flaky: "Fix flaky tests", limiter: "Rate limiter"])
    }()

    /// Cleanup requests about the made-up processes: two that were decided and two that wait.
    static func requests(for sample: Sample) -> [CleanupRequest] {
      let now = sample.takenAt
      let processes = sample.observation.snapshot.processes
      func target(_ pid: Int32) -> [ProcessRecord.Key] {
        processes.filter { $0.pid == pid }.map(\.key)
      }
      let checkout = SessionID(harness: .claudeCode, value: "demo-checkout")
      return [
        CleanupRequest(
          id: "demo0001", createdAt: now - 7200, requester: checkout,
          reason: "The test run is over, its watcher can go.", targets: target(100_104),
          status: .done, decidedAt: now - 7000,
          outcome: CleanupRequest.Outcome(ended: 3, endedByForce: 0, survived: 0, refused: 0)),
        CleanupRequest(
          id: "demo0002", createdAt: now - 5400, requester: nil,
          reason: "Free memory before the build.", targets: target(100_300), status: .denied,
          decidedAt: now - 5300),
        CleanupRequest(
          id: "demo0003", createdAt: now - 240, requester: checkout,
          reason: "The dev server was only needed for the preview, which is done.",
          targets: target(100_102)),
        CleanupRequest(
          id: "demo0004", createdAt: now - 60, requester: nil,
          reason: "Clean up before the nightly build.", targets: target(100_300)),
      ]
    }
  }
#endif
