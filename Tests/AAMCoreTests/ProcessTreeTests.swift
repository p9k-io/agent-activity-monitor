import AAMCore
import Testing

struct ProcessTreeTests {
  let tree = ProcessTree([
    .make(10, parent: 1),
    .make(11, parent: 10),
    .make(12, parent: 11),
    .make(13, parent: 10),
    .make(20, parent: 1),
  ])

  @Test func `descendants cover every generation below the root`() {
    #expect(tree.descendants(of: 10).map(\.pid).sorted() == [11, 12, 13])
  }

  @Test func `descendants of a leaf or an unknown process are empty`() {
    #expect(tree.descendants(of: 12).isEmpty)
    #expect(tree.descendants(of: 999).isEmpty)
  }

  @Test func `ancestors are listed nearest first and stop where the snapshot ends`() {
    #expect(tree.ancestors(of: 12).map(\.pid) == [11, 10])
  }

  @Test func `a process that claims to be its own parent does not loop forever`() {
    let looping = ProcessTree([.make(5, parent: 5), .make(6, parent: 5)])

    #expect(looping.descendants(of: 5).map(\.pid) == [6])
    #expect(looping.ancestors(of: 6).map(\.pid) == [5])
  }

  @Test func `a process is found by its identifier`() {
    #expect(tree.process(13)?.parentPID == 10)
    #expect(tree.process(999) == nil)
  }
}
