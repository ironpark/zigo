# GOALS

## Problem and the end result from the user's point of view

`LinkMode.dynamic` currently selects a Zig shared-library build, but zigo does not define a runtime
loading contract, validate the installed artifact, or exercise dynamic linkage in examples and CI.
All generated Go calls still go through cgo. Users should be able to opt into a purego backend,
build their application with `CGO_ENABLED=0`, load the matching zigo shared library explicitly or
through a documented default, and retain the same public Go API and lifecycle behavior.

## Measurable goals

- Make `.link_mode = .dynamic` a tested macOS/Linux artifact contract with predictable filenames,
  exported symbols, dependencies, and installation behavior.
- Add an opt-in `.backend = .purego` generation mode; keep `.cgo` as the compatibility default.
- Preserve the public package's function, handle, error, tagged-union, and callback types across
  backends. Backend selection may only change private/raw implementation files and loader APIs.
- Run a generated callback-free example and a retained-callback example with `CGO_ENABLED=0` against
  the produced shared library on every supported host CI target.
- Make missing libraries, wrong architecture, missing symbols, duplicate loads, and callback panics
  deterministic typed failures with regression coverage.

## Supported scope and non-goals

- Initial support is native macOS and Linux on amd64/arm64, matching both zigo's executable
  reflection constraint and purego Tier 1 desktop support. Windows, mobile, and Tier 2 targets are
  follow-up work.
- A shared library remains a platform/architecture-specific artifact. purego removes the C compiler
  from the Go application build; it does not make one Zig library portable across targets.
- Static linking remains cgo-only. `.backend = .purego` requires `.link_mode = .dynamic`.
- Do not expose Zig-only values or structs by value. Continue using the existing C ABI scalar,
  pointer, opaque handle, and out-parameter lowering.
- Do not unload a successfully registered library during process lifetime; generated function
  pointers and live native handles make safe unloading impossible without a larger ownership model.
- Do not silently rewrite an existing user-owned `go.mod`. Create the pinned requirement when zigo
  creates a module, otherwise diagnose and document the required `go get` command.

## Reference source / commit / license

- purego upstream: `github.com/ebitengine/purego`, stable tag `v0.10.2`, Apache-2.0. Its supported
  API surface for this plan is `Dlopen`, `Dlsym`, `RegisterFunc`, and `NewCallback`.
- purego remains pre-v1 beta software. Pin the tested version and isolate all usage in generated raw
  backend files so an upstream API migration does not affect zigo's public Go API.
- Zig toolchain baseline: Zig 0.16.0. Go baseline remains 1.23, or 1.24 with `auto_cleanup`.

## Completion criteria for the whole plan

- The dynamic-library and purego examples pass generation, stale-output, ABI, symbol, loader,
  `CGO_ENABLED=0 go test`, and failure-path tests on macOS/Linux amd64/arm64.
- The existing cgo examples and public API snapshots remain green.
- README/wiki explain build-time versus runtime requirements, library discovery, packaging, callback
  limits, and backend/platform support without claiming cross-target Zig generation.
