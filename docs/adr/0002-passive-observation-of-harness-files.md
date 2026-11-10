# Session state is read passively from Harness files, never through hooks

Session identity and state come from files the Harnesses already write for themselves (the Claude Code session registry and transcripts, the Codex thread store and rollout files). We do not install hooks and we do not edit any Harness configuration. Hooks are documented and more precise, but they change the user's agent setup, and an observer that works the moment it is installed matters more to us than precision.

## Consequences

- These file formats are internal and undocumented. They can change with any Harness release.
- Every Harness adapter must degrade to an unknown state instead of failing when a file is missing or its shape is unexpected.
- Some states are not visible from outside, for example a Session waiting on a permission prompt.
