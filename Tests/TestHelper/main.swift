import Darwin

// A stand-in process for tests. It is not an Apple binary, so the system exposes its
// environment the way it does for the tools a Harness starts.
//
//   aam-test-helper sleep <seconds>        waits and exits
//   aam-test-helper become-sleep <seconds> waits for a byte on standard input, then replaces
//                                          itself with /bin/sleep <seconds>
//   aam-test-helper ignore-term <seconds>  waits, ignoring a polite request to end
//   aam-test-helper tree <seconds>         starts a copy of itself that sleeps, then waits
let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 2, let seconds = UInt32(arguments[1]) else {
  fputs("usage: aam-test-helper sleep|become-sleep|ignore-term|tree <seconds>\n", stderr)
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
case "ignore-term":
  signal(SIGTERM, SIG_IGN)
  sleep(seconds)
case "tree":
  var child: pid_t = 0
  let path = CommandLine.arguments[0]
  let childArguments: [UnsafeMutablePointer<CChar>?] = [
    strdup(path), strdup("sleep"), strdup(String(seconds)), nil,
  ]
  guard posix_spawn(&child, path, nil, nil, childArguments, nil) == 0 else { exit(71) }
  sleep(seconds)
default:
  exit(64)
}
