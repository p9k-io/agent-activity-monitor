# Agent Activity Monitor

A native macOS app, a command line tool (`aam`) and an MCP server that show which processes exist because of AI coding agent sessions, what is heating the machine right now, and what can safely go. This repository is public.

## Read first

- [GLOSSARY.md](GLOSSARY.md) is the domain language. Use its words in code, tests, UI text and commit messages, and avoid the words it lists under _Avoid_.
- [docs/adr/](docs/adr/) holds the decisions that must not be undone by accident. Read the one that covers the area you are changing.

## Layout

- `Sources/AAMCore/`: the domain with no I/O. Model, Attribution, Stale rules, Culprit ranking, Cleanup proposals, history and reports.
- `Sources/AAMPlatform/`: macOS adapters. Process sources, Harness adapters, Host adapters, the store, the Sampler, the MCP server.
- `Sources/AAMCleanup/`: the only code that ends processes. Only the app links it.
- `Sources/aam/`: the command line tool, including `aam mcp`.
- `App/`: the SwiftUI app. `App/project.yml` is an XcodeGen spec; the Xcode project is generated and not committed. The app holds views and their model only; anything worth a test belongs in the package.
- `Tests/`: Swift Testing suites with synthetic fixtures.

## Commands

- `scripts/check.sh` runs every gate in order, cheapest first. Run it before you push.
- `swift test` runs the tests. `swift test --enable-code-coverage && scripts/check-coverage.sh` also checks the coverage floors.
- `swift format --in-place --recursive Package.swift Sources Tests App/Sources` formats. CI runs the same paths with `lint --strict`.
- `xcodegen generate --spec App/project.yml` generates `App/AgentActivityMonitor.xcodeproj`.
- `scripts/run-app.sh` builds the app and runs it. The app lives in the menu bar; these arguments make it easier to look at:
  - `-showWindow YES` opens the main window at launch, `-section projects` or `-section stale` chooses what it shows.
  - `-showPanel YES` (debug builds only) shows the menu bar panel in an ordinary window.
  - `-demo YES` (debug builds only) shows made-up Sessions and processes instead of the machine. Nothing real is read, and a Cleanup confirmed in this mode finds nothing to end. Use it to look at Cleanup dialogs and to take screenshots.

## Rules

- **Only the app terminates processes** ([ADR 0001](docs/adr/0001-only-the-app-terminates-processes.md)). The command line tool and the MCP server read and file Cleanup requests. Nothing else. `scripts/check-boundaries.sh` enforces it.
- **Tests never signal a process they did not start themselves.** No test may touch a real Session.
- **Never confirm a Cleanup of something real while checking the app.** Look at Cleanup dialogs in demo mode. To check a Cleanup end to end, start `aam-test-helper`, file a request for it against a scratch store (`AAM_STORE`), and confirm only after reading that the dialog lists nothing but that helper. Address buttons by their accessibility identifier, never by position.
- **Fixtures are synthetic.** No real project names, paths, user names, Session identifiers or command lines from anyone's machine.
- **Never store or log command lines, environment values or transcript content.** Environment variables are read by name from an explicit list.
- **`AAMCore` does no I/O.** Files, processes, the clock and the database are reached through protocols implemented in `AAMPlatform`. Mock only at that boundary.
- **Harness adapters degrade to unknown** when a file is missing or has an unexpected shape ([ADR 0002](docs/adr/0002-passive-observation-of-harness-files.md)). They never throw into the sampler.
- **Public system interfaces only** ([ADR 0003](docs/adr/0003-public-apis-only.md)).
- **The app runs all the time, so a look must stay cheap** ([ADR 0004](docs/adr/0004-always-running-sampler-with-lineage.md)). The budget is under 1 % of one core on average. What does not change is read once and kept; what is expensive is done every few looks. Measure before and after a change to the Sampler or to anything it calls.
- Check a change to the app by looking at it: run it, capture the window, compare what it shows with `aam … --json`.
- Write the failing test first. Tests finish within 5 seconds each.
- In an `async` test, do not call `Process.waitUntilExit` after an `await`: it runs the run loop of the thread it is called on, which may not be the one the process reports to, and then it never returns. Wait for the termination handler instead, as `RunningHelper.exit()` does.
- UI text, identifiers, comments and documentation are in English.
- Commits follow Conventional Commits. Pull requests are squash-merged, so the pull request title is the commit message.

## Deviations from the DX Heroes engineering standard

- Biome, Knip, TypeScript, Vitest, Playwright, pnpm and Node do not apply: this is a Swift repository. Their counterparts are swift-format (2 spaces, 100 columns), the Swift 6 language mode and Swift Testing.
- Coverage floors are 90 % for `AAMCore` and `AAMCleanup` and 70 % for `AAMPlatform`, because adapters at the system boundary can only partly run without a live machine. The command line tool and the app are thin shells and are not measured.
- The 500-line limit is enforced per file by `scripts/check-file-length.sh` and per function by review, because swift-format has no such rule.
- release-please uses `release-type: simple`, because there is no `package.json`.
- Docker, deployment and runtime configuration do not apply: this is a desktop app.

## Ship recipe
- Integrace: branch + PR (squash)
- Release: merging the release-please PR creates tag vX.Y.Z and the GitHub Release; only prokopsimek merges it
- Deploy: none
- Ověření: CI is green on main; `aam --version` prints the tagged version
- Board: none
