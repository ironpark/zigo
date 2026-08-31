# SCOPE

Move one documentation file, update one instruction file, add one relative symbolic link, and verify the resulting filesystem and Git state.

# CONTEXT

## Current implementation and bottlenecks

`tool.md` and `AGENTS.md` are currently at the repository root. The worktree already contains unrelated user changes that must remain untouched.

## Target structure and invariants

The canonical planr instructions live at `docs/.agent/tool.md`; `AGENTS.md` points there; `CLAUDE.md` resolves to the same repository instructions through a relative symlink. Unrelated changes remain byte-for-byte untouched.
