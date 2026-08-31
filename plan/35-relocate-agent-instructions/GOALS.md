# GOALS

## Problem and the end result from the user's point of view

The repository-level agent guidance points to a root-level `tool.md`; relocate that guidance into `docs/.agent/` and expose equivalent instructions to Claude-compatible agents.

## Measurable goals

- `tool.md` exists at `docs/.agent/tool.md` and no longer exists at the repository root.
- `AGENTS.md` references the relocated file.
- `CLAUDE.md` is a symbolic link to `AGENTS.md`.

## Supported scope and non-goals

Only agent instruction file organization is in scope. Existing source, examples, and unrelated plans are not modified.

## Reference source / commit / license

The existing repository files and the user's request are the sole references; no external code or license applies.

## Completion criteria for the whole plan

The requested path changes are present, links resolve, repository guidance references the correct location, and the changes are committed without disturbing pre-existing worktree edits.
