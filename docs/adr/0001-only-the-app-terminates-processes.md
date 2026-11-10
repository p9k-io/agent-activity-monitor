# Only the app terminates processes, and only after a person confirms

The `aam` command line tool and the MCP server never send a signal to any process. They read, and they file Cleanup requests; the app is the single place where a Cleanup runs, and it runs only after a person approves it in the app. We chose this over letting a Session clean up after itself because a Harness that ends the wrong process costs someone their work, and the caller of a CLI cannot be trusted to know which Session it speaks for.

## Consequences

- A Session cannot tidy up unattended. It can only ask.
- Cleanup requests need the app to be running to be decided.
- Before any signal the app re-checks the process identifier together with the process start time, so a recycled identifier is never hit.
- The code that sends signals lives in its own module, `AAMCleanup`. Only the app links it. `scripts/check-boundaries.sh` fails the build when anything else imports it or sends a signal.
