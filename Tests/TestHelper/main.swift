import Darwin

// A stand-in process for tests: `aam-test-helper sleep <seconds>` waits and exits.
// It is not an Apple binary, so the system exposes its environment the way it does for the
// tools a Harness starts.
let arguments = CommandLine.arguments.dropFirst()
guard arguments.first == "sleep", let seconds = arguments.dropFirst().first.flatMap(UInt32.init)
else {
  fputs("usage: aam-test-helper sleep <seconds>\n", stderr)
  exit(64)
}
sleep(seconds)
