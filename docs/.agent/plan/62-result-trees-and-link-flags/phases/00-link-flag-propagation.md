---
completed_at: "2026-09-01T23:02:02Z"
perf_phase: false
status: done
---
> DONE-WHEN: Docs describe every input's fate; generated raw file shows `#cgo pkg-config:`
> NEXT: none

# Link flag rules and pkg-config propagation

## Planned Work

- Document in `configuration.md` and 03 §12 the current propagation rule per
  input (system lib, pkg-config, framework, weak framework, `lib_paths`,
  `rpaths`, `include_dirs`) and what `cgo_flags` replaces versus keeps; note
  purego emits no directives and static archives need system libraries at Go
  link time.
- build.zig: emit a separate `--pkg-config-libs` list for `.system_lib` entries
  with `use_pkg_config != .no`; keep `-l` for `.no`; collect `lib_paths` as
  `-L` flags; pass `weak` frameworks as `-weak_framework`.
- emit: render `#cgo pkg-config: a b` before the LDFLAGS line when the list is
  non-empty; make `cgo_flags` override semantics match the documented choice.
- generator.zig tests for each new line; an example (or the `flags` generator
  test) linking a pkg-config library on the CI host if one is available,
  otherwise a rendered-text assertion only.

## Done When

- Docs describe every input's fate; generated raw file shows `#cgo pkg-config:`
  for pkg-config libraries and `-L` for `lib_paths`; generator tests cover the
  lines; `zig build test` and example `go-check` runs green; committed.
