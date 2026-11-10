# Contributing

## Setup

You need macOS 26, Xcode 26 and XcodeGen (`brew install xcodegen`).

```sh
scripts/check.sh
```

runs every gate that CI runs: formatting, file length, tests with coverage floors, a release build of the package and a build of the app.

## How we work

- Read [GLOSSARY.md](GLOSSARY.md) and use its words. If a change needs a new term, add it there in the same pull request.
- Write the failing test first, then the code that makes it pass.
- Keep `AAMCore` free of I/O. Anything that touches files, processes, the clock or the database goes behind a protocol in `AAMPlatform`.
- Test fixtures are synthetic. Do not paste process lists, paths or session files from a real machine.
- Tests must not signal any process they did not start themselves.
- A decision that is hard to reverse, surprising, and the result of a real trade-off gets a short record in [docs/adr/](docs/adr/).

## Adding a Harness

A Harness adapter finds the Sessions of one agent program and reports their identity and state. It reads only what that program already writes for itself, and it returns an unknown state when a file is missing or looks different from what it expects. Add fixtures for the shapes you support and for a broken one.

## Commits and pull requests

Commits follow [Conventional Commits](https://www.conventionalcommits.org/). Pull requests are squash-merged, so the pull request title becomes the commit message and ends up in the changelog. Say what changed for the person using the app.
