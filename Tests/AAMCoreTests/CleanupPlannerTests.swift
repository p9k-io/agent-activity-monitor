import AAMCore
import Testing

struct CleanupPlannerTests {
  let planner = CleanupPlanner(ownUser: 501, protected: [900])
  let root = ProcessRecord.make(100, path: "/opt/bin/claude")
  let child = ProcessRecord.make(101, parent: 100, path: "/opt/bin/node")
  let grandchild = ProcessRecord.make(102, parent: 101, path: "/opt/bin/esbuild")
  let bystander = ProcessRecord.make(200, path: "/opt/bin/other")

  func plan(_ keys: [ProcessRecord.Key], _ processes: [ProcessRecord]) -> CleanupPlan {
    planner.plan(for: keys, in: Snapshot(takenAt: epoch, processes: processes))
  }

  @Test func `a Cleanup ends the target and everything it started, the target first`() {
    let plan = plan([root.key], [grandchild, bystander, child, root])

    #expect(plan.targets.map(\.pid) == [100, 101, 102])
    #expect(plan.refused.isEmpty)
  }

  @Test func `a process named twice, or already covered by another target, is ended once`() {
    let plan = plan([child.key, root.key, child.key], [root, child, grandchild])

    #expect(plan.targets.map(\.pid) == [100, 101, 102])
  }

  @Test func `a process identifier that now belongs to another process is not touched`() {
    let recycled = ProcessRecord.make(100, path: "/bin/sleep", startedAfter: 500)

    let plan = plan([root.key], [recycled])

    #expect(plan.targets.isEmpty)
    #expect(plan.refused == [CleanupPlan.Refusal(process: root.key, reason: .gone)])
  }

  @Test func `a process that has ended already is reported as gone`() {
    let plan = plan([root.key], [bystander])

    #expect(plan.refused.map(\.reason) == [.gone])
  }

  @Test func `another user's process is refused`() {
    let foreign = ProcessRecord.make(300, path: "/usr/libexec/daemon", user: 0)

    let plan = plan([foreign.key], [foreign])

    #expect(plan.targets.isEmpty)
    #expect(plan.refused.map(\.reason) == [.notYours])
  }

  @Test(arguments: [Int32(1), 900])
  func `the system's first process and protected processes are refused`(pid: Int32) {
    let special = ProcessRecord.make(pid, parent: 0, path: "/sbin/special")

    let plan = plan([special.key], [special])

    #expect(plan.targets.isEmpty)
    #expect(plan.refused.map(\.reason) == [.protected])
  }

  @Test func `a protected process below a target is left running while the rest is ended`() {
    let app = ProcessRecord.make(900, parent: 101, path: "/Applications/Monitor.app/Monitor")
    let appChild = ProcessRecord.make(901, parent: 900, path: "/bin/ps")

    let plan = plan([root.key], [root, child, grandchild, app, appChild])

    #expect(plan.targets.map(\.pid) == [100, 101, 102])
  }

  @Test func `a zombie is refused, because there is nothing left to end`() {
    let zombie = ProcessRecord.make(105, parent: 100, path: "node", zombie: true)

    let plan = plan([zombie.key, root.key], [root, zombie])

    #expect(plan.targets.map(\.pid) == [100])
    #expect(plan.refused == [CleanupPlan.Refusal(process: zombie.key, reason: .zombie)])
  }

  @Test func `a target without its descendants ends that process alone`() {
    let plan = planner.plan(
      for: [root.key], in: Snapshot(takenAt: epoch, processes: [root, child]),
      includingDescendants: false)

    #expect(plan.targets.map(\.pid) == [100])
  }
}
