---
depends_on:
- "201-api-consistency-refactor#2"
perf_phase: false
status: planned
---
> DONE-WHEN: `grep -rn "func (.*) Zigo" examples/*/go*` returns nothing.
> NEXT: none

# Generated Go conventions

## Planned Work

- Unexport lifecycle methods in multi-package builds: `ZigoAcquire/ZigoRelease/ZigoPoison/ZigoAcquireChild/ZigoDropChild` become `zigo*`; `internal/lifecycle` reaches them through an unexported interface or a generated adapter in each package.
- Force raw packages under `internal/`; reject other `raw_package` paths at build time. Update examples 02 and 07.
- `Must*` companions: pick one policy (always off unless MUST plugin enabled, and drop degenerate void `Must*` methods).
- `Checked` suffix: give the three meanings distinct names (iterator error-returning variant, optional-returning variant, bounds-checked variant) in `src/gen/naming.zig` and the iterator plugin.
- With `features.implements`, hide the original zigo-shaped method by default; add an option to keep it. Use `int`/`int64` counts consistently in stdlib-shaped methods.
- Callback type naming: use the binding name when unique, prefix with owner type only on collision; never repeat the parameter name.
- Optional values: choose one spelling for input and output (recommend `(T, bool)` output and `*T` input stays, but document; or `optional.Value[T]`); at minimum make `Invert(value *bool) (bool, bool)` shapes impossible by naming the presence result.
- Prefix functional options with the type name by default (`TerminalOption`, `WithTerminalRows`).
- Reject Go package names that collide with stdlib packages (`errors`, `io`, `fmt`, ...) with a diagnostic; rename example 02's package.
- Emit interface assertions for every handle that implements `io.Reader`/`io.Writer`/`io.StringWriter`.
- Regenerate all examples; update `docs/reference/generated-go-api.md`.

## Done When

- `grep -rn "func (.*) Zigo" examples/*/go*` returns nothing.
- `go vet ./...` and `go test ./...` pass in every example; `zig build go-verify` passes.
