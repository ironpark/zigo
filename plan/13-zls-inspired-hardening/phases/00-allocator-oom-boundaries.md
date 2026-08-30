---
perf_phase: false
status: in-progress
---
> DONE-WHEN: No generator implementation path uses `std.heap.page_allocator`.
> NEXT: none

# Harden allocator and OOM boundaries

## Planned Work

- Give `generator.generate` an internal scratch arena so its allocation lifetime no longer depends on an undocumented caller convention.
- Thread caller-owned allocators through validation and borrowed-result emission, propagate OOM, and update call sites.
- Make ABI diff, sync-check, and snapshot difference builders safe under partial allocation failure.
- Add allocation-failure coverage with `std.testing.checkAllAllocationFailures` where APIs are expected to be OOM-safe.

## Done When

- No generator implementation path uses `std.heap.page_allocator`.
- Validation cannot silently skip symbol collision checks on allocation failure.
- Focused allocation-failure tests and the full Zig test suite pass under Zig 0.16.0.
