---
completed_at: "2026-08-30T11:58:38Z"
depends_on:
- "30-go-user-experience#1"
perf_phase: false
status: done
---
> DONE-WHEN: Users can run registered report and doctor steps without modifying generated output; reports include final public names, symbols, ownership and relevant semantics, and doctor failures identify a concrete corrective action.
> NEXT: none

# Binding Report and Environment Doctor

## Planned Work

- Add read-only generator commands that render an effective binding report and diagnose Go version, cgo, gofmt, native-target, and auto-cleanup prerequisites.
- Expose report and doctor run handles from `GoBindings` and register them through the standard-step helper.
- Add parser, snapshot, success, and expected-failure tests with actionable diagnostics.

## Done When

- Users can run registered report and doctor steps without modifying generated output; reports include final public names, symbols, ownership and relevant semantics, and doctor failures identify a concrete corrective action.
