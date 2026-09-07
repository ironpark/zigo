---
completed_at: "2026-09-07T15:18:28Z"
perf_phase: false
status: done
---
> DONE-WHEN: Semantic comparison and affected example checks pass; documentation matches code; changes committed.
> NEXT: none

# Initial Work

## Planned Work

- Apply Context and selector migrations, group lifetime declarations, align guides, and regenerate any ordering-only artifacts.

## Done When

- Semantic comparison and affected example checks pass; documentation matches code; changes committed.

## Implementation and validation

- Added public Context usage to 05, 08, 09, 10; shared batch type references; explicit selectors for union and I/O member lists.
- Removed redundant Ticker receiver roles and grouped root freeStream destructor with Stream members. Preserved 03 as Entry.members teaching baseline, namespace scopes, discovery policy, and full output-buffer schema.
- Updated example READMEs, feature-to-example guide, binding guide, changelog and historical audit follow-up.
- Against ebed77a0: six comptime normalized deep comparisons passed (queue comparison restores only freeStream declaration position). Actual queue semantic.json differs only in top-level functions order; all other fields and function entries match exactly. Generated cgo/purego diffs are declaration/registration ordering only.
- Six examples passed `zig build test go-check go-lib abi-check go-coverage`; 07/08/11 also passed purego-go-check and purego-go-lib; 10 passed go-check/go-lib with -Dpurego.
- Fresh `go test -count=1 ./...` passed in all six cgo modules and four affected purego modules with CGO_ENABLED=0.
- Root `zig build test --summary all`: 318/318 steps, 765/765 tests passed. Zig formatting and git diff --check passed.
