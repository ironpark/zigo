# GOALS

## Problem and the end result from the user's point of view

The project needs an evidence-based review of existing Zig type placement that traces canonical implementations before judging owners, declaration forms, public paths, visibility, and files. The result is a durable assessment report, not an automatic source reorganization.

## Measurable goals

- Install and run the current `ziglyzer` tool against the production `build.zig` and `src/` sources.
- Inventory every reported type and lexical nesting, and generate per-file reports with explicit roots where useful.
- Record every production type using the requested assessment schema and one of the three allowed final assessments.
- Check import-cycle risk, compatibility paths, tests, documentation, and any configured file-splitting policy before recommending changes.

## Supported scope and non-goals

Production Zig sources in `build.zig` and under `src/` are in scope. Tests, examples, and documentation are searched as consumers and supporting evidence. Moving or renaming implementation code is out of scope for this review.

## Reference source / commit / license

The current repository worktree and the locally installed `ziglyzer` built from `/Users/ironpark/Projects/Personal/research/zig-struct` are the reference sources. No third-party source is copied.

## Completion criteria for the whole plan

The checked-in review report contains a complete per-type assessment for `build.zig` and `src/`, cites generated evidence, identifies unresolved AST cases, and is validated against current tests and clean-tree checks.
