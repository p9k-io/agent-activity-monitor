import AAMCore
import AAMPlatform
import Foundation
import Testing

struct GitProjectResolverTests {
  let scratch: TemporaryDirectory
  let resolver = GitProjectResolver()

  init() throws {
    scratch = try TemporaryDirectory()
  }

  @Test func `a directory inside a repository belongs to the repository root`() throws {
    let root = try scratch.directory("alpha")
    try scratch.directory("alpha/.git")
    let nested = try scratch.directory("alpha/packages/web/src")

    #expect(resolver.project(for: nested.path) == Project(root: root.path))
  }

  @Test func `the repository root is its own Project`() throws {
    let root = try scratch.directory("alpha")
    try scratch.directory("alpha/.git")

    #expect(resolver.project(for: root.path) == Project(root: root.path))
  }

  @Test func `a worktree belongs to its main repository's Project`() throws {
    let main = try scratch.directory("alpha")
    try scratch.directory("alpha/.git/worktrees/feature")
    let worktree = try scratch.directory("worktrees/feature")
    try scratch.file(
      "worktrees/feature/.git", "gitdir: \(main.path)/.git/worktrees/feature\n")
    let nested = try scratch.directory("worktrees/feature/src")

    #expect(resolver.project(for: worktree.path) == Project(root: main.path))
    #expect(resolver.project(for: nested.path) == Project(root: main.path))
  }

  @Test func `a directory outside any repository is its own Project`() throws {
    let plain = try scratch.directory("notes/today")

    #expect(resolver.project(for: plain.path) == Project(root: plain.path))
  }

  @Test func `a git file that is not a worktree pointer keeps its directory as the root`() throws {
    let module = try scratch.directory("alpha/vendor/lib")
    try scratch.file("alpha/vendor/lib/.git", "gitdir: ../../.git/modules/lib\n")

    #expect(resolver.project(for: module.path) == Project(root: module.path))
  }
}
