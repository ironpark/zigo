---
perf_phase: false
status: in-progress
---
> DONE-WHEN: Regenerated purego trees contain no `callbackRegistryMu`; `zig build
> NEXT: none

# Lock-free registry lookup

## Planned Work

- Rewrite the emitted purego registry to `sync.Map`: store in
  `NewCallbackHandle`, `LoadAndDelete` + drain in `DeleteCallbackHandle`,
  `Load` + per-entry protocol in `acquireCallback`; delete
  `callbackRegistryMu`. Keep token allocation, `activeCallbackHandles`, and
  the entry drain protocol as they are.
- Emit the delete-vs-acquire invariant comment.
- Add/extend a purego `-race`-capable test (run under the cgo-free
  constraint the suite already handles): concurrent invocations racing
  DeleteCallbackHandle, plus concurrent create/delete churn; assert no lost
  drains (`ActiveCallbackHandleCount` returns to baseline) and no
  invocation after delete completes.
- Update purego goldens.

## Done When

- Regenerated purego trees contain no `callbackRegistryMu`; `zig build
  test` passes; callback examples (04, 05, 07, 08) pass their purego test
  suites including the new churn test.
