---
depends_on:
- "104-transitive-link-inputs-and-pkg-config#0"
perf_phase: false
status: planned
---
> DONE-WHEN: `linkSystemLibrary("avformat", .{ .use_pkg_config = .force })` emits `#cgo pkg-config: libavformat` on a machine where only that spelling resolves, and an unresolvable name fails at `zig build go` with the diagnostic.
> NEXT: none

# Build-time pkg-config resolution

## Planned Work

- For each `.force` pkg-config library, probe `pkg-config --exists <name>` then `lib<name>` and emit the spelling that resolves; fail the `go` step with a diagnostic naming library and declaring module when neither does; fall back to the original name with a warning when `pkg-config` is absent; tests with a fake `pkg-config` on PATH; docs and CHANGELOG.

## Done When

- `linkSystemLibrary("avformat", .{ .use_pkg_config = .force })` emits `#cgo pkg-config: libavformat` on a machine where only that spelling resolves, and an unresolvable name fails at `zig build go` with the diagnostic.
