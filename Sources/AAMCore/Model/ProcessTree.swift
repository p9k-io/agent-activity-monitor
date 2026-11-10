/// Parent and child links between the processes of one snapshot.
public struct ProcessTree: Sendable {
  private let byPID: [Int32: ProcessRecord]
  private let childrenByParent: [Int32: [Int32]]

  public init(_ processes: [ProcessRecord]) {
    byPID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
    var children: [Int32: [Int32]] = [:]
    for process in processes where process.parentPID != process.pid {
      children[process.parentPID, default: []].append(process.pid)
    }
    childrenByParent = children
  }

  public func process(_ pid: Int32) -> ProcessRecord? {
    byPID[pid]
  }

  public func children(of pid: Int32) -> [ProcessRecord] {
    (childrenByParent[pid] ?? []).compactMap { byPID[$0] }
  }

  /// Every process below `pid`, in no particular order. The root itself is not included.
  public func descendants(of pid: Int32) -> [ProcessRecord] {
    var result: [ProcessRecord] = []
    var visited: Set<Int32> = [pid]
    var pending = childrenByParent[pid] ?? []
    while let next = pending.popLast() {
      guard visited.insert(next).inserted, let record = byPID[next] else { continue }
      result.append(record)
      pending.append(contentsOf: childrenByParent[next] ?? [])
    }
    return result
  }

  /// The chain of parents above `pid`, nearest first, as far as the snapshot reaches.
  public func ancestors(of pid: Int32) -> [ProcessRecord] {
    var result: [ProcessRecord] = []
    var visited: Set<Int32> = [pid]
    var next = byPID[pid]?.parentPID
    while let parent = next, visited.insert(parent).inserted, let record = byPID[parent] {
      result.append(record)
      next = record.parentPID
    }
    return result
  }
}
