import AAMCore
import Foundation
import Testing

struct CleanupProposerTests {
  let alpha = Project(root: "/work/alpha")
  let root = ProcessRecord.make(100, path: "/opt/bin/claude", rss: 300, terminal: true)
  let server = ProcessRecord.make(101, parent: 100, path: "/opt/bin/node", rss: 200)
  let worker = ProcessRecord.make(102, parent: 101, path: "/opt/bin/esbuild", rss: 100)
  let bystander = ProcessRecord.make(900, path: "/usr/libexec/other", rss: 50)

  func session(
    _ state: SessionState = .idle, title: String? = "fix the build", resume: String? = nil
  ) -> Session {
    Session.make(
      "s1", root: root, title: title, state: state,
      lastActivity: epoch.addingTimeInterval(-7200), resume: resume)
  }

  func proposer(
    _ processes: [ProcessRecord], sessions: [Session] = [], protected: Set<Int32> = []
  ) -> CleanupProposer {
    let snapshot = Snapshot(takenAt: epoch, processes: processes)
    let reading = Reading(
      snapshot: snapshot, sessions: sessions,
      inventory: Attributor().inventory(of: snapshot, sessions: sessions, memory: .empty))
    return CleanupProposer(
      reading: reading, planner: CleanupPlanner(ownUser: 501, protected: protected))
  }

  func finding(
    _ kind: StaleFinding.Kind, _ reason: StaleFinding.Reason, title: String = "node",
    session: SessionID? = nil, _ processes: [ProcessRecord], canCleanUp: Bool = true
  ) -> StaleFinding {
    StaleFinding(
      kind: kind, reason: reason, title: title, project: alpha, session: session,
      processes: processes.map(\.key), residentBytes: 0, canCleanUp: canCleanUp)
  }

  // MARK: Ending a Session

  @Test func `ending a Session ends everything attributed to it and nothing else`() throws {
    let proposal = try #require(
      proposer([root, server, worker, bystander], sessions: [session()])
        .ending(session().id))

    #expect(proposal.title == "End the Session \"fix the build\"?")
    #expect(proposal.message == "Claude Code in alpha. Last active 2h 0m ago.")
    #expect(proposal.means == .endProcesses)
    #expect(proposal.targets.map(\.process.pid) == [100, 101, 102])
    #expect(proposal.targets.map(\.kind) == [.harness, .other, .other])
    #expect(proposal.targets.allSatisfy { $0.session?.id == session().id })
    #expect(proposal.residentBytes == 600)
    #expect(proposal.cautions.isEmpty)
    #expect(proposal.canProceed)
  }

  @Test func `a Session without a title is called by its Project`() throws {
    let untitled = session(title: nil)

    let proposal = try #require(proposer([root], sessions: [untitled]).ending(untitled.id))

    #expect(proposal.title == "End the Session \"alpha\"?")
  }

  @Test func `ending a Session offers the command that reopens it`() throws {
    let resumable = session(resume: "claude --resume s1")

    let proposal = try #require(proposer([root], sessions: [resumable]).ending(resumable.id))

    #expect(
      proposal.resume == [
        CleanupProposal.Resume(
          session: resumable.id, title: "fix the build", command: "claude --resume s1")
      ])
  }

  @Test(arguments: [
    (
      SessionState.working,
      "The Session \"fix the build\" is working right now. Ending it stops that work in the middle."
    ),
    (.waiting, "The Session \"fix the build\" is waiting for your answer."),
    (.background, "Work the Session \"fix the build\" started is still running in the background."),
    (.unknown, "What the Session \"fix the build\" is doing cannot be told from outside."),
  ])
  func `a Session that is not idle comes with a caution`(state: SessionState, caution: String)
    throws
  {
    let busy = session(state)

    let proposal = try #require(proposer([root], sessions: [busy]).ending(busy.id))

    #expect(proposal.cautions == [caution])
  }

  @Test func `a working Session is not described by when it was last active`() throws {
    let busy = session(.working)

    let proposal = try #require(proposer([root], sessions: [busy]).ending(busy.id))

    #expect(proposal.message == "Claude Code in alpha.")
  }

  @Test func `there is nothing to propose for a Session that is not there`() {
    #expect(proposer([bystander]).ending(session().id) == nil)
  }

  @Test func `what must not be ended is listed as left alone`() throws {
    let proposal = try #require(
      proposer([root, server, worker], sessions: [session()], protected: [100])
        .ending(session().id))

    #expect(proposal.refused == [CleanupPlan.Refusal(process: root.key, reason: .protected)])
    #expect(proposal.targets.map(\.process.pid) == [101, 102])
  }

  // MARK: Cleaning up findings

  @Test func `one finding is proposed by its name and the reason it is Stale`() throws {
    let idle = finding(
      .idleDevServer, .serverIdle(since: epoch.addingTimeInterval(-3 * 3600)),
      session: session().id, [server])

    let proposal = try #require(
      proposer([root, server, worker], sessions: [session()]).cleaningUp([idle]))

    #expect(proposal.title == "Clean up \"node\"?")
    #expect(proposal.message == "Idle dev server in alpha: no CPU use for 3h 0m.")
    #expect(proposal.asked == [server.key])
    #expect(proposal.targets.map(\.process.pid) == [101, 102])
    #expect(proposal.resume.isEmpty)
  }

  @Test func `several findings are proposed together`() throws {
    let beta = ProcessRecord.make(500, path: "/opt/bin/vite", cwd: "/work/beta")
    let first = finding(.idleDevServer, .serverIdle(since: epoch), session: session().id, [server])
    let second = StaleFinding(
      kind: .ownerlessLeftover, reason: .orphan(formerSession: nil, since: nil),
      title: "Left behind in beta", project: Project(root: "/work/beta"), session: nil,
      processes: [beta.key], residentBytes: 0)

    let proposal = try #require(
      proposer([root, server, worker, beta], sessions: [session()]).cleaningUp([first, second]))

    #expect(proposal.title == "Clean up 2 findings?")
    #expect(proposal.message == "In 2 Projects.")
    #expect(proposal.targets.map(\.process.pid) == [500, 101, 102])
  }

  @Test func `a finding that cannot be cleaned up is left out`() throws {
    let zombie = ProcessRecord.make(105, parent: 100, path: "node", zombie: true)
    let stuck = finding(.ownerlessLeftover, .zombie(parent: 100), [zombie], canCleanUp: false)
    let idle = finding(.idleDevServer, .serverIdle(since: epoch), [server])
    let proposer = proposer([root, server, zombie], sessions: [session()])

    #expect(proposer.cleaningUp([stuck]) == nil)
    let proposal = try #require(proposer.cleaningUp([stuck, idle]))
    #expect(proposal.title == "Clean up \"node\"?")
    #expect(proposal.asked == [server.key])
  }

  @Test func `an Idle session among the findings is ended like any Session`() throws {
    let waiting = session(.waiting, resume: "claude --resume s1")
    let idle = finding(
      .idleSession, .sessionIdle(since: epoch.addingTimeInterval(-90_000)),
      title: "fix the build", session: waiting.id, [root, server, worker])

    let proposal = try #require(
      proposer([root, server, worker], sessions: [waiting]).cleaningUp([idle]))

    #expect(proposal.message == "Idle session in alpha: no activity for 1d 1h.")
    #expect(proposal.cautions == ["The Session \"fix the build\" is waiting for your answer."])
    #expect(proposal.resume.map(\.command) == ["claude --resume s1"])
  }

  @Test func `an older copy of a server is only probably left behind, and the proposal says so`()
    throws
  {
    let older = finding(
      .ownerlessLeftover, .olderDuplicate(of: 150), session: session().id, [server])

    let proposal = try #require(
      proposer([root, server], sessions: [session(.working)]).cleaningUp([older]))

    #expect(
      proposal.cautions == [
        "A newer copy of \"node\" runs in the same Session, so the older one is probably left "
          + "behind. If the Session still uses it, what it offers stops working there."
      ])
  }

  // MARK: Culprits

  @Test func `the web content of an application can be ended`() throws {
    let helper = ProcessRecord.make(700, path: "/System/WebKit/com.apple.WebKit.WebContent")
    let culprit = Culprit(
      id: "machine:web-content:com.example.app", title: "Web content of Example", owner: .none,
      cpuPercent: 120, residentBytes: 0, processes: [helper.key],
      load: .webContent(application: "com.example.app"))

    let proposal = try #require(proposer([helper, bystander]).ending(culprit))

    #expect(proposal.title == "End \"Web content of Example\"?")
    #expect(proposal.means == .endProcesses)
    #expect(proposal.targets.map(\.process.pid) == [700])
    #expect(proposal.targets.first?.kind == nil)
    #expect(
      proposal.cautions == [
        "The pages go blank or load again, depending on the application. "
          + "What was typed into a page and not saved is lost."
      ])
  }

  @Test func `a simulator is shut down by its device, not by ending its processes`() throws {
    let device = "AAAAAAAA-1111-4222-8333-BBBBBBBBBBBB"
    let launchd = ProcessRecord.make(800, path: "/Library/CoreSimulator/launchd_sim")
    let culprit = Culprit(
      id: "machine:simulator:\(device)", title: "iOS Simulator · Phone 99", owner: .none,
      cpuPercent: 300, residentBytes: 0, processes: [launchd.key],
      load: .simulator(device: device))

    let proposal = try #require(proposer([launchd]).ending(culprit))

    #expect(proposal.title == "Shut down \"iOS Simulator · Phone 99\"?")
    #expect(proposal.means == .shutDownSimulator(device: device))
    #expect(proposal.targets.map(\.process.pid) == [800])
  }

  @Test(arguments: [
    InducedLoad.Kind.simulator(device: nil), .virtualMachine, nil,
  ])
  func `nothing is proposed for load that can only be shown`(load: InducedLoad.Kind?) {
    let process = ProcessRecord.make(800, path: "/usr/libexec/something")
    let culprit = Culprit(
      id: "machine:x", title: "something", owner: .none, cpuPercent: 300, residentBytes: 0,
      processes: [process.key], load: load)

    #expect(proposer([process]).ending(culprit) == nil)
  }

  @Test func `a Culprit that is a Session is ended as that Session`() throws {
    let busy = session(.working)
    let culprit = Culprit(
      id: "session:\(busy.id)", title: "fix the build", owner: .session(busy.id, alpha),
      cpuPercent: 200, residentBytes: 0, processes: [root.key, server.key])
    let proposer = proposer([root, server, worker], sessions: [busy])

    let asSession = try #require(proposer.ending(busy.id))
    #expect(proposer.ending(culprit) == asSession)
  }

  // MARK: Cleanup requests

  func request(_ targets: [ProcessRecord], by requester: SessionID? = nil) -> CleanupRequest {
    CleanupRequest(
      id: "r1", createdAt: epoch, requester: requester, reason: "not needed any more",
      targets: targets.map(\.key))
  }

  @Test func `a request is proposed with who asked and with what its targets started`() {
    let request = request([server], by: session().id)

    let proposal = proposer([root, server, worker], sessions: [session()]).answering(request)

    #expect(proposal.title == "Approve Cleanup request r1?")
    #expect(proposal.message == "Asked for by the Session \"fix the build\", Claude Code in alpha.")
    #expect(proposal.request == request)
    #expect(proposal.targets.map(\.process.pid) == [101, 102])
    #expect(proposal.cautions.isEmpty)
  }

  @Test func `a request can come from a Session that has ended, or from outside any`() {
    let gone = SessionID(harness: .codex, value: "gone")
    let proposer = proposer([bystander])

    #expect(
      proposer.answering(request([bystander], by: gone)).message
        == "Asked for by a Session that has ended.")
    #expect(
      proposer.answering(request([bystander])).message == "Asked for from outside any Session.")
  }

  @Test func `a request that would end a whole Session says so, with what the Session is doing`() {
    let busy = session(.working)

    let proposal = proposer([root, server], sessions: [busy]).answering(request([root]))

    #expect(
      proposal.cautions == [
        "This ends the whole Session \"fix the build\".",
        "The Session \"fix the build\" is working right now. "
          + "Ending it stops that work in the middle.",
      ])
  }

  @Test func `a request for another Session's processes says whose they are`() {
    let otherRoot = ProcessRecord.make(200, path: "/opt/bin/codex", terminal: true)
    let other = Session.make("s2", root: otherRoot, harness: .codex, title: "the other one")

    let proposal = proposer([root, server, otherRoot], sessions: [session(), other])
      .answering(request([server], by: other.id))

    #expect(
      proposal.cautions == [
        "Processes of the Session \"fix the build\" are among these, and it is not the one asking."
      ])
  }

  @Test func `a request whose processes are gone has nothing left to end`() {
    let proposal = proposer([bystander]).answering(request([server]))

    #expect(!proposal.canProceed)
    #expect(proposal.refused == [CleanupPlan.Refusal(process: server.key, reason: .gone)])
  }
}
