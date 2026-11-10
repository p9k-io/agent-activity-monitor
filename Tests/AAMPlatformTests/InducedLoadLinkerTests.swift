import AAMCore
import AAMPlatform
import Foundation
import Testing

struct SimulatorLinkerTests {
  let scratch: TemporaryDirectory
  let udid = "AAAAAAAA-1111-4222-8333-BBBBBBBBBBBB"

  init() throws {
    scratch = try TemporaryDirectory()
  }

  func snapshot() -> Snapshot {
    .of(
      .make(
        900, path: "/usr/libexec/launchd_sim",
        arguments: [
          "launchd_sim",
          "/somewhere/CoreSimulator/Devices/\(udid)/data/var/run/launchd_bootstrap.plist",
        ]),
      .make(901, parent: 900, path: "/Library/Developer/CoreSimulator/x/backboardd"),
      .make(902, parent: 901, path: "/Library/Developer/CoreSimulator/x/SpringBoard"),
      .make(950, path: "/opt/bin/node"))
  }

  @Test func `a simulator and everything running inside it are one piece of induced load`() throws {
    let load = try #require(
      SimulatorLinker(devices: scratch.url).inducedLoad(in: snapshot()).first)

    #expect(load.processes.map(\.pid).sorted() == [900, 901, 902])
    #expect(load.id == "simulator:\(udid)")
    #expect(load.kind == .simulator(device: udid))
  }

  @Test func `a simulator whose device cannot be told is still a simulator`() throws {
    let load = try #require(
      SimulatorLinker(devices: scratch.url)
        .inducedLoad(in: .of(.make(900, path: "/usr/libexec/launchd_sim"))).first)

    #expect(load.kind == .simulator(device: nil))
  }

  @Test func `the simulator is named after its device when the device record can be read`() throws {
    try scratch.file(
      "\(udid)/device.plist",
      """
      <?xml version="1.0" encoding="UTF-8"?>
      <plist version="1.0"><dict><key>name</key><string>Phone 99 Pro</string></dict></plist>
      """)

    let load = try #require(
      SimulatorLinker(devices: scratch.url).inducedLoad(in: snapshot()).first)

    #expect(load.title == "iOS Simulator · Phone 99 Pro")
  }

  @Test func `without a device record the simulator is still named`() throws {
    let load = try #require(
      SimulatorLinker(devices: scratch.url).inducedLoad(in: snapshot()).first)

    #expect(load.title == "iOS Simulator")
  }
}

struct WebContentLinkerTests {
  let renderer =
    "/System/Library/Frameworks/WebKit.framework/XPCServices/"
    + "com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent"

  func linker(open: [Int32: [String]] = [:], mapped: [Int32: [String]] = [:]) -> WebContentLinker {
    WebContentLinker(
      files: DeclaredOpenFiles(byPID: open, mapped: mapped), applicationName: { _ in nil })
  }

  @Test func `web content is grouped by the application whose storage it has mapped`() {
    let snapshot = Snapshot.of(
      .make(10, path: renderer), .make(11, path: renderer), .make(12, path: renderer))

    let loads = linker(mapped: [
      10: ["/usr/lib/dyld", "/Users/dev/Library/WebKit/com.example.terminal/WebsiteData/db"],
      11: ["/Users/dev/Library/WebKit/com.example.terminal/WebsiteData/other"],
      12: ["/Users/dev/Library/WebKit/com.example.browser/WebsiteData/db"],
    ]).inducedLoad(in: snapshot)

    let terminal = loads.first { $0.id == "web-content:com.example.terminal" }
    #expect(loads.count == 2)
    #expect(terminal?.title == "Web content of com.example.terminal")
    #expect(terminal?.kind == .webContent(application: "com.example.terminal"))
    #expect(terminal?.processes.map(\.pid).sorted() == [10, 11])
  }

  @Test func `storage held as an open file names the application too`() {
    let snapshot = Snapshot.of(.make(10, path: renderer))

    let loads = linker(open: [10: ["/Users/dev/Library/WebKit/com.example.terminal/db"]])
      .inducedLoad(in: snapshot)

    #expect(loads.map(\.id) == ["web-content:com.example.terminal"])
  }

  @Test func `web content whose application cannot be told is left ungrouped`() {
    let snapshot = Snapshot.of(.make(10, path: renderer))

    #expect(
      linker(open: [10: ["/dev/null"]], mapped: [10: ["/usr/lib/dyld"]])
        .inducedLoad(in: snapshot).isEmpty)
  }

  @Test func `web content is named after the application when the system knows its name`() {
    let linker = WebContentLinker(
      files: DeclaredOpenFiles(mapped: [10: ["/Users/dev/Library/WebKit/com.example.terminal/db"]]),
      applicationName: { $0 == "com.example.terminal" ? "Example Terminal" : nil })

    let loads = linker.inducedLoad(in: .of(.make(10, path: renderer)))

    #expect(loads.map(\.title) == ["Web content of Example Terminal"])
    #expect(loads.map(\.id) == ["web-content:com.example.terminal"])
  }

  @Test func `the application of a web content process is looked up once`() {
    let files = CountingFiles(mapped: [
      10: ["/Users/dev/Library/WebKit/com.example.terminal/db"],
      11: ["/usr/lib/dyld"],
    ])
    let linker = WebContentLinker(files: files, applicationName: { _ in nil })
    let snapshot = Snapshot.of(.make(10, path: renderer), .make(11, path: renderer))

    let first = linker.inducedLoad(in: snapshot)
    let second = linker.inducedLoad(in: snapshot)

    #expect(first == second)
    #expect(first.map(\.id) == ["web-content:com.example.terminal"])
    // Each helper is asked once for its open files and once for its mapped files.
    #expect(files.timesAsked == 4)
  }

  @Test func `other processes are not asked for their files`() {
    let snapshot = Snapshot.of(.make(20, path: "/opt/bin/node"))

    let loads = linker(mapped: [20: ["/Users/dev/Library/WebKit/com.example.terminal/x"]])
      .inducedLoad(in: snapshot)

    #expect(loads.isEmpty)
  }
}

struct LibprocMappedFilesTests {
  @Test func `a file the current process has mapped into memory is found`() throws {
    let scratch = try TemporaryDirectory()
    let file = try scratch.file("mapped.bin", String(repeating: "x", count: 4096))
    let descriptor = open(file.path, O_RDONLY)
    #expect(descriptor >= 0)
    defer { close(descriptor) }
    let mapping = mmap(nil, 4096, PROT_READ, MAP_PRIVATE, descriptor, 0)
    #expect(mapping != MAP_FAILED)
    defer { munmap(mapping, 4096) }

    let found = LibprocOpenFiles().firstMappedFile(of: getpid()) { $0.hasSuffix("/mapped.bin") }

    #expect(found == file.path)
  }

  @Test func `nothing is found when no mapped file matches`() {
    #expect(LibprocOpenFiles().firstMappedFile(of: getpid()) { _ in false } == nil)
  }
}

struct VirtualMachineLinkerTests {
  let machine =
    "/System/Library/Frameworks/Virtualization.framework/XPCServices/"
    + "com.apple.Virtualization.VirtualMachine.xpc/Contents/MacOS/"
    + "com.apple.Virtualization.VirtualMachine"

  @Test func `a virtual machine is named after the tool whose disk image it runs`() {
    let files = DeclaredOpenFiles(byPID: [
      30: ["/Users/dev/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"],
      31: ["/Users/dev/.local/share/containers/podman/machine/applehv/machine.raw"],
    ])

    let loads = VirtualMachineLinker(files: files)
      .inducedLoad(in: .of(.make(30, path: machine), .make(31, path: machine)))

    #expect(loads.map(\.title) == ["Virtual machine of Docker", "Virtual machine of Podman"])
  }

  @Test func `a virtual machine nobody recognises is still named for what it is`() {
    let loads = VirtualMachineLinker(files: DeclaredOpenFiles(byPID: [30: ["/dev/null"]]))
      .inducedLoad(in: .of(.make(30, path: machine)))

    #expect(loads.map(\.title) == ["Virtual machine"])
    #expect(loads.map(\.kind) == [.virtualMachine])
    #expect(loads.first?.processes.map(\.pid) == [30])
  }

  @Test func `the tool behind a virtual machine is looked up once`() {
    let files = CountingFiles(open: [30: ["/x/com.docker.docker/Docker.raw"]])
    let linker = VirtualMachineLinker(files: files)
    let snapshot = Snapshot.of(.make(30, path: machine))

    _ = linker.inducedLoad(in: snapshot)
    let asked = files.timesAsked
    _ = linker.inducedLoad(in: snapshot)

    #expect(files.timesAsked == asked)
  }

  @Test func `other processes are not virtual machines`() {
    let files = DeclaredOpenFiles(byPID: [40: ["/x/com.docker.docker/Docker.raw"]])

    #expect(
      VirtualMachineLinker(files: files).inducedLoad(in: .of(.make(40, path: "/opt/bin/node")))
        .isEmpty)
  }
}
