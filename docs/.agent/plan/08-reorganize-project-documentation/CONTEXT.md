# SCOPE

Relocate six existing documents, add a wiki index plus detailed usage and limitations pages, rewrite README, and repair all affected links.

# CONTEXT

## Current implementation and bottlenecks

`docs/` contains architecture records, constraints, an implementation plan, and a review in one flat directory. README duplicates detailed material and makes the quick start difficult to scan.

## Target structure and invariants

Keep historical and implementation-facing material under `docs/design/`. Keep user-facing operational guidance under `docs/wiki/`. README must link into both areas without repeating their detail. Preserve factual behavior and verified Zig/Go commands.
