import Darwin

// A stand-in process for tests. It is not an Apple binary, so the system exposes its
// environment the way it does for the tools a Harness starts.
//
//   aam-test-helper sleep <seconds>        waits and exits
//   aam-test-helper become-sleep <seconds> waits for a byte on standard input, then replaces
//                                          itself with /bin/sleep <seconds>
let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 2, let seconds = UInt32(arguments[1]) else {
  fputs("usage: aam-test-helper sleep|become-sleep <seconds>\n", stderr)
  exit(64)
}

switch arguments[0] {
case "sleep":
  sleep(seconds)
case "become-sleep":
  var byte: UInt8 = 0
  _ = read(STDIN_FILENO, &byte, 1)
  let program = strdup("/bin/sleep")
  let argument = strdup(String(seconds))
  execv("/bin/sleep", [program, argument, nil])
  exit(70)
default:
  exit(64)
}
