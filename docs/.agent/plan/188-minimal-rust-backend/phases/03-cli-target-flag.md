---
completed_at: "2026-09-10T04:44:43Z"
depends_on:
- "188-minimal-rust-backend#2"
perf_phase: false
status: done
---
> DONE-WHEN: `zigo-gen generate --target rust ...` writes a Rust tree; without `--target`
> NEXT: none

# Select the target from the command line

## Planned Work

- Add the output-language flag to `zigo-gen generate`, resolved through
  `targets.byName` with an error naming the known targets. Default `"go"`, so
  every existing invocation is unchanged.

  **Divergence: the flag is `--output-target`, not `--target` as planned.**
  This CLI has already spent the word "target" on build platforms:
  `doctor --target native|cross` and `generate --cgo-target <goos>/<goarch>`
  both mean a machine. Adding a `--target` that means a language one
  subcommand away from a `--target` that means a platform is the same
  ambiguity plan 187 spent its phase 0 removing from the plugin contract.
  `--output-target` also matches `generator.Options.output_target`, the name
  the field already had.

  **Divergence: `cli.zig` does not resolve the name.** Its test module is
  built with no imports at all, so importing `targets` would have forced a
  module graph on it. It carries the name as a string and `src/main.zig`
  resolves it, which is also where the "known targets are go, rust"
  diagnostic belongs.
- Replace `src/main.zig`'s `outputTarget()` stub with the parsed value, and
  thread it to `generate` and `abi-diff`.

  **Divergence: `report` is deliberately left on the Go default** rather than
  given the flag, behind a named `reportTarget()`. Every line `report` renders
  is a Go import path, a Go package layout or a cgo link line, so answering
  `--output-target rust` with a Go-shaped report would be worse than not
  accepting the flag. A Rust report is its own piece of work.
- Rename the formatter override flag only where it is target-neutral: keep
  `--gofmt` working (plan 186's decision, user-visible surface) and add
  `--rustfmt` as the Rust formatter's `override_flag`. Both feed the same
  `formatter_executable`; a flag that does not match the selected target is an
  error rather than silently ignored.
- Update the usage text and the CLI contract tests, including a process-level
  test that an unknown target exits non-zero and names the valid targets.
- Also added, beyond the plan: a process-level test that generates the Rust
  crate *through the CLI* and then compiles it with `rustc -D warnings`. The
  case runner calls `generator.generate` directly, so it never exercised the
  flag, the emitter-table dispatch and `rustfmt` together.

## Done When

- `zigo-gen generate --output-target rust ...` writes a Rust tree, and that
  tree compiles; without the flag the output is byte-identical to today's.
- `--output-target haskell` exits 2 and its stderr names `go` and `rust`.
- A formatter flag naming another language is refused, not ignored.
- `cli.zig` tests cover both flags and the unknown-target error.
- `zig build test --summary all` green; generator cases clean; thirteen
  examples green; `zig fmt --check` clean. Committed.
