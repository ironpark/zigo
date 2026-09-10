---
depends_on:
- "188-minimal-rust-backend#2"
perf_phase: false
status: planned
---
> DONE-WHEN: `zigo-gen generate --target rust ...` writes a Rust tree; without `--target`
> NEXT: none

# Select the target from the command line

## Planned Work

- Add `--target <name>` to `zigo-gen generate` in `src/gen/cli.zig`, resolved
  through `targets.byName` with an error naming the known targets. Default
  `"go"`, so every existing invocation is unchanged.
- Replace `src/main.zig`'s `outputTarget()` stub with the parsed value, and
  thread it to the `generate`, `abi-diff` and `report` paths that already call
  it.
- Rename the formatter override flag only where it is target-neutral: keep
  `--gofmt` working (plan 186's decision, user-visible surface) and add
  `--rustfmt` as the Rust formatter's `override_flag`. Both feed the same
  `formatter_executable`; a flag that does not match the selected target is an
  error rather than silently ignored.
- Update the usage text and the CLI contract tests, including a process-level
  test that `--target nope` exits non-zero and names the valid targets.

## Done When

- `zigo-gen generate --target rust ...` writes a Rust tree; without `--target`
  the output is byte-identical to today's.
- `--target nope` exits 2 and its stderr names `go` and `rust`.
- `cli.zig` tests cover both flags and the unknown-target error.
- `zig build test --summary all` green; generator cases clean; thirteen
  examples green; `zig fmt --check` clean. Committed.
