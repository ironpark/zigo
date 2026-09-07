---
completed_at: "2026-09-07T13:58:41Z"
depends_on:
- "156-binding-authoring-polish#0"
- "156-binding-authoring-polish#1"
perf_phase: false
status: done
---
> DONE-WHEN: Examples and docs demonstrate all improvements, validation passes and the final commits leave a clean working tree.
> NEXT: none

# Idiomatic examples and documentation

## Planned Work

- Remove source-equivalent parameter names; keep intentional overrides and all semantic contracts.
- Use local scopes, member groups, explicit shared selectors, shared result contracts and readable layouts in examples.
- Update all current API docs and migration guidance; retain one explicit full-contract example.
- Compare semantic content allowing only intentional provenance and ordering changes, run full tests, all example ABI/generated-tree checks and fresh cgo/purego Go tests.

## Done When

- Examples and docs demonstrate all improvements, validation passes and the final commits leave a clean working tree.

## Implementation and Verification

- Reviewed all 13 binding files; removed 145 source-equivalent name overrides, reducing name-only literals from 126 to 5. Preserved intentional renames and explicit userdata/cancellation linkage names.
- Grouped type members with local scopes, shared explicit generic export selectors, extracted event-queue type/package constants and shared owned-result contracts.
- Preserved a full-schema output buffer example in io-streams. Longest event-queue/telemetry binding lines are now 113/90 characters (previously 319/351).
- Updated authoring, callback, lifetime, migration, diagnostic and quick-reference docs, and Unreleased notes.
- Added final reflection regressions for static constructors and sparse callback byte-pair/userdata lowering, plus member/name replacement checks.
- Compared all 13 semantic snapshots against 8893a270 by stable function/type/constructor identity. The only differences are declaration order and 145 name_source transitions from sidecar to ast; all other nested content matches exactly.
- Passed zig test src/root.zig (11 tests), and zig build test --summary all (311/311 steps, 765/765 tests).
- All 13 examples passed Zig tests, go-check, go-lib, abi-check and go-coverage, followed by fresh cgo Go tests. All 7 purego examples passed generated-tree/library checks and CGO_ENABLED=0 Go tests.
- git diff --check passed. Source and generated changes are committed before phase completion.
