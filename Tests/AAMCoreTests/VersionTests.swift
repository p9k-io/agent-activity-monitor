import AAMCore
import Testing

@Test func `version is a semantic version`() {
  let parts = AAM.version.split(separator: ".")

  #expect(parts.count == 3)
  #expect(parts.allSatisfy { Int($0) != nil })
}
