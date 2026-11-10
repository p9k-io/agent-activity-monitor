# Agent Activity Monitor

Shows which processes exist because of AI coding agent sessions, what is heating the machine right now, and what can safely go.

## Language

**Harness**:
An AI coding agent program that runs sessions, such as Claude Code or Codex CLI.
_Avoid_: agent, CLI, tool

**Session**:
One running instance of a Harness working in a directory on a person's behalf.
_Avoid_: agent, conversation, thread, tab

**Project**:
The directory a Session works in, identified by its git repository root, or by the working directory when there is none. Worktrees belong to their main repository's Project.
_Avoid_: workspace, repo

**Host**:
The application a Session's terminal lives in, such as cmux, iTerm or VS Code.
_Avoid_: terminal, workspace

**Session tree**:
A Session's root process and all its descendants.
_Avoid_: process group, children

**Induced load**:
Processes that run because of work done in a Project but live outside every Session tree: simulators, browser content processes, containers, indexing.
_Avoid_: indirect processes, side effects

**Attribution**:
The link from a process to the Session or Project it exists for. Every Attribution carries its Evidence.

**Evidence**:
Why an Attribution holds. Tree: a descendant. Tagged: carries the Session's marker. Remembered: was seen in the Session tree earlier. Inferred: working directory or timing.
_Avoid_: confidence, score

**Culprit**:
Anything consuming enough CPU right now to heat the machine, attributed or not.
_Avoid_: hog, offender

**Stale**:
No longer needed; a candidate for Cleanup. Kinds: Idle session, Ownerless leftover, Forgotten induced load, Idle dev server.
_Avoid_: dead, unused, garbage

**Idle session**:
A Session that is not working and has had no activity for longer than the idle threshold.

**Ownerless leftover**:
A process its owner no longer needs: an Orphan, a zombie, or an older duplicate of a server within one Session.

**Orphan**:
A process that outlived the Session it was attributed to.

**Idle dev server**:
A long-running server or watcher that has used almost no CPU for longer than its threshold while its Session is idle or gone.

**Cleanup**:
Terminating Stale things. Only a person can approve a Cleanup.
_Avoid_: kill, reap, purge

**Cleanup request**:
A proposal to clean up specific targets, filed by a Session or a script, waiting for a person's decision.

**Resume command**:
The command that reopens an ended Session with its conversation intact.
