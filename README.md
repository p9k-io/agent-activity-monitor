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

aam request-cleanup 4242 --reason "left over from my test run"
aam requests    # Cleanup requests and what was decided about them
```

`aam` never ends a process. A Session that wants something gone files a Cleanup request, and a person decides about it in the app.

What `aam` and the app remember (which process belonged to which Session, and when a Session ended) is kept in `~/Library/Application Support/io.p9k.agent-activity-monitor/aam.sqlite`. Set `AAM_STORE` to keep it somewhere else.

## For agents

`aam mcp` serves the same facts over the Model Context Protocol, so a Session can see what is attributed to it and ask for a Cleanup of what it no longer needs. Connect it yourself; the app never changes a Harness's configuration.

```sh
claude mcp add aam -- aam mcp    # Claude Code
codex mcp add aam -- aam mcp     # Codex CLI
```

| Tool | What it does |
| --- | --- |
| `list_sessions` | The running Sessions with Project, state, memory and Resume command. |
| `my_session` | The Session the server runs in and what is attributed to it. |
| `list_culprits` | What is using CPU right now and whom it belongs to. |
| `list_stale` | What is no longer needed, and why. |
| `request_cleanup` | Files a Cleanup request for a person to decide in the app. |
| `get_request` | What was decided about a Cleanup request. |

None of them ends a process. At most 50 requests wait for a decision at a time, and a request names at most 100 processes.

## Cleanup

Nothing is ended without a dialog that lists it first. The dialog shows every process a Cleanup would end, how much memory that frees, what is left alone and why, and what you should know before you say yes: that a Session is working right now, or that an older copy of a server is only probably left behind.

- **Stale** offers a Cleanup for each finding, or for all of them at once.
- **Projects** ends a Session with everything attributed to it and gives you the command that reopens it.
- **Overview** shuts a simulator down with Xcode's own tool and ends the web content of an application. Virtual machines and system processes are only shown.
- **Requests** lists what Sessions and scripts asked for. Approve or deny each one.

Each process is asked to exit. What has not exited after 5 seconds is ended by force. Only your own processes can be ended, never the app itself or what it runs under, and a process identifier that now belongs to another process is never touched.

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

builds it and runs it with its window open. Without the argument it starts in the menu bar only. With `-demo YES` it shows made-up Sessions instead of your machine, which is how to look around without anything real at stake.

## Documentation

- [GLOSSARY.md](GLOSSARY.md): the words this project uses and what they mean.
- [docs/adr/](docs/adr/): the decisions behind the design.
- [CONTRIBUTING.md](CONTRIBUTING.md): how to work on it.

## License

[MIT](LICENSE)
