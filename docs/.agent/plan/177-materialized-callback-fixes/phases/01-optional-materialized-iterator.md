---
completed_at: "2026-09-08T04:22:44Z"
depends_on:
- "177-materialized-callback-fixes#0"
perf_phase: false
status: done
---
> DONE-WHEN: cgo and purego cover present/absent/error returns and iterator exhaustion/early stop; all checks pass and changes are committed.
> NEXT: none

# optional-materialized-iterator

## Planned Work

- Support optional and error-union optional materialized returns through validation, lowering, native serialization, Go decoding, and iterator projection.

## Done When

- cgo and purego cover present/absent/error returns and iterator exhaustion/early stop; all checks pass and changes are committed.
