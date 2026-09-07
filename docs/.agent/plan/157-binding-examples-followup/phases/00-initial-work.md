---
completed_at: "2026-09-07T14:05:02Z"
perf_phase: false
status: done
---
> DONE-WHEN: Findings and validation limits are recorded and communicated; review artifacts are committed.
> NEXT: none

# Initial Work

## Planned Work

- Inspect all examples, trace remaining friction to implementation, and write an evidence-backed review.

## Done When

- Findings and validation limits are recorded and communicated; review artifacts are committed.

## Review Results

- Read all 13 binding examples and recorded five prioritized findings in docs/.agent/reviews/binding-examples-followup.md.
- Confirmed contextual receiver inference and unnamed userdata/cancellation fallback links with a temporary compile-time probe.
- Fresh go-check and abi-check passed for callback, event-queue, io-streams and materialized.
- No executable or generated changes were made; runtime-suite results from the preceding implementation are not claimed as new validation.
