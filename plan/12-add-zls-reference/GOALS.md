# GOALS

## Problem and the end result from the user's point of view

Provide a local, untracked checkout of the zls 0.16.x development line for source reference.

## Measurable goals

- `ref/` is ignored by Git.
- `ref/zls` is a valid clone of `github.com/zigtools/zls` on the requested 0.16.x ref.

## Supported scope and non-goals

Only the repository ignore rule, local shallow clone, and plan record are in scope. Do not modify zls or vendor it into this repository.

## Reference source / commit / license

Use the official `https://github.com/zigtools/zls.git` repository and record the resolved branch and commit.

## Completion criteria for the whole plan

The ignored checkout exists, its origin/ref are verified, tracked changes are committed, and the phase is done.
