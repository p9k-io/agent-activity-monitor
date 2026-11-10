# The app samples continuously and remembers lineage

When a Session ends, its surviving processes are re-parented to `launchd` and the link to the Session is gone. A Session marker in the environment survives only in some processes: the system hides the environment of Apple's own binaries, and Codex starts its servers with a stripped environment. So the app runs all the time, samples the process table, and records which Session each process belonged to. An on-demand tool that looks only when opened could attribute an Orphan by guesswork alone.

## Consequences

- The app starts at login and has a budget of under 1 % CPU on average.
- The command line tool works without the app, with weaker Attribution of Orphans.
- The lineage record stores process identifiers, start times and Session identifiers, never command lines.
