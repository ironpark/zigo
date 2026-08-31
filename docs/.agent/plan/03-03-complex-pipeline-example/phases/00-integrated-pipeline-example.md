---
completed_at: "2026-08-30T00:49:52Z"
perf_phase: false
status: done
---
> DONE-WHEN: `zig build test`, `zig build go`, `zig build go-check`, and `zig build abi-check` pass in the example.
> NEXT: none

# Integrated Pipeline Example

## Planned Work

- Implement the Zig pipeline, generic batch specializations, explicit error sets, callback contract, lifecycle counters, and zlib `compressBound` probe.
- Configure zigo semantics and specializations, then generate and retain the Go wrapper, C shim, error lock, manifest, and ABI baseline.
- Add Zig unit tests plus Go end-to-end, typed-error, callback-panic, idempotent-close, concurrent-lifecycle, generic, and system-link tests.
- Add a Go benchmark and concise README with generation and verification commands.
- Include `examples/05-pipeline` in CI and run the repository regression suite.

## Done When

- `zig build test`, `zig build go`, `zig build go-check`, and `zig build abi-check` pass in the example.
- `go test -count=1 ./...` passes and asserts both callback-handle and native-live-byte counters return to zero, including after concurrent use.
- `go test -run '^$' -bench BenchmarkPipelineProcess -benchmem` completes and reports timing and allocation metrics.
- Root `zig build test` passes, CI lists the new example, and `git diff --check` is clean.
