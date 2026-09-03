---
completed_at: "2026-09-03T01:36:33Z"
perf_phase: false
status: done
---
> DONE-WHEN: No same-name different-body predicates remain; goldens unchanged; report test added; tests green.
> NEXT: none

# Merge identical predicates and split same-name concepts

## Planned Work

- Move `functionHasCallback` and the shared `isStringSliceParameter` onto `semantic` (methods or a small `semantic` helper namespace) and use them from lower and validate.
- Rename validate's `sliceReturnElement` to reflect its release-target meaning; keep emit's.
- Fix report's `constructorForInit` to match emit; add a report test covering a method constructor.
- Decide and test the `[*:0]const u8` element case so validate, lower, and emit agree.

## Done When

- No same-name different-body predicates remain; goldens unchanged; report test added; tests green.
