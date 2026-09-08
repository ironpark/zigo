# SCOPE

`src/gen/go_walk.zig`, `src/gen/sync_check.zig` and `build/steps.zig`.

# CONTEXT

## Current implementation and bottlenecks

`std.Io.Dir.SelectiveWalker` joins parts with `std.fs.path.sep`, so walked
paths use `\` on Windows while emitters, the manifest and diagnostics all use
`/`. `PublishGeneratedGo` compared the two with `std.ascii.eqlIgnoreCase`, and
`sync_check.compare` compared walked paths against recorded differences with
`std.mem.eql`. POSIX runs never saw the mismatch because both spellings agree
there, which is why the whole test suite passes on Linux and macOS.

## Target structure and invariants

`go_walk` owns the comparison: `eqlPath` treats `\` and `/` as the same
separator and compares case-insensitively, and `portableAlloc` respells a
walked path before it is recorded. Paths that leave the walker are always
portable.
