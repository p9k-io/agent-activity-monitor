# Agent Activity Monitor

> Early development. Nothing is released yet.

A native macOS app that shows which processes exist because of AI coding agent sessions, what is heating your Mac right now, and what can safely go.

## The problem

A day of parallel sessions in Claude Code or Codex CLI leaves hundreds of processes behind: MCP servers, dev servers, language servers, simulators, browser panes. The fan spins up, and Activity Monitor cannot tell you which session any of it belongs to or whether it is still needed.

Much of the load is not even inside a session's process tree. A simulator an agent booted, a browser pane it opened for a check, a container it started: these run under `launchd`, far from the session that caused them.

## What it does

Planned for the first release:

- Groups processes by project and session, for Claude Code and Codex CLI.
- Ranks what is consuming CPU right now and says which session or project it belongs to, including load outside the session's process tree.
- Flags what is no longer needed: sessions idle for a day, orphaned servers, duplicated MCP servers, dev servers nobody is using, simulators and browser panes left running.
- Ends a session together with its leftovers and gives you the command that resumes it.
- Keeps 30 days of history, so you can see what was busy an hour ago and where CPU time went.
- Offers the same data to scripts and agents through the `aam` command line tool and an MCP server.

## Command line

`aam` reads the same data as the app and prints it as a table, or as JSON with `--json`.

```sh
aam sessions    # running Sessions with their Project, state and memory
aam ps          # processes grouped by Project and Session, each with its Evidence
aam culprits    # what is consuming CPU right now and whom it belongs to
aam stale       # what is no longer needed, and why
aam mine        # the Session this command runs in and what is attributed to it
```

`aam` never ends a process.

What `aam` and the app remember (which process belonged to which Session, and when a Session ended) is kept in `~/Library/Application Support/io.p9k.agent-activity-monitor/aam.sqlite`. Set `AAM_STORE` to keep it somewhere else.

## Principles

- **A person approves every cleanup.** The command line tool and the MCP server can ask for one. Only the app carries it out, after you confirm.
- **It only reads.** It does not install hooks and does not change any agent's configuration.
- **It stays on your Mac.** No telemetry. Command lines, environment values and conversation content are never stored.

## Build from source

Requires macOS 26 and Xcode 26.

```sh
swift build
swift test
```

The app is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`):

```sh
scripts/run-app.sh -showWindow YES
```

builds it and runs it with its window open. Without the argument it starts in the menu bar only.

## Documentation

- [GLOSSARY.md](GLOSSARY.md): the words this project uses and what they mean.
- [docs/adr/](docs/adr/): the decisions behind the design.
- [CONTRIBUTING.md](CONTRIBUTING.md): how to work on it.

## License

[MIT](LICENSE)
