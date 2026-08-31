---
completed_at: "2026-08-30T00:25:26Z"
depends_on:
- "01-zigo-go-bindings#10"
perf_phase: false
status: done
---
> DONE-WHEN: CI is green on macOS and Linux from a clean checkout.
> NEXT: none

# Hardening and release readiness

## Planned Work

- Install a panic handler in the shim that returns -2 and records a message retrievable
  through `zg_last_error_message`, documenting that this is diagnosable failure and not
  recovery.
- Observe the user library's `linkSystemLibrary` calls and reflect them into the `#cgo`
  directives, so framework and system-library links carry through.
- Honour a user-supplied `cgo_flags` override for deployments that relocate the library.
- Add a CI workflow building all four examples on macOS and Linux and running
  `zig build test`, `zig build go-check`, `zig build abi-check` and `go test`.
- Record a cgo call-overhead benchmark in CI so regressions are visible.
- Bring `README.md` and the `docs/` set in line with the shipped behaviour.

## Done When

- CI is green on macOS and Linux from a clean checkout.
- A deliberate Zig panic behind the boundary yields code -2 and a readable message.
- An example linking a system library builds without hand-edited cgo directives.
- The benchmark result is recorded in the CI log.
