# SCOPE

This plan changes the build API, generated C ABI for the purego backend, Go raw/runtime emitters,
callback support, doctor/report output, examples, fixtures, and CI. The semantic declaration model
and public Go API remain backend-neutral. Shared artifact embedding and cross-target reflection are
explicit future extensions.

# CONTEXT

## Current implementation and bottlenecks

- `Options.link_mode` already maps `.dynamic` to `b.addLibrary(.linkage = .dynamic)`, installs the
  artifact, and links libc, but no test checks `.so`/`.dylib` identity, exported symbols, loadability,
  runtime dependency resolution, or actual dynamic execution.
- The raw emitter always generates `import "C"`, `#cgo` flags, C scalar conversions, and
  `runtime/cgo`. The backend is therefore structural rather than a small link-mode switch.
- The lowered ABI is already purego-friendly: it contains integers, floats, opaque/pointer values,
  and one native return. Slices and error-union payloads use pointer/length or out parameters, and no
  struct crosses the C boundary by value.
- Callbacks are the blocking incompatibility. The Zig shim currently references a fixed Go
  `//export` trampoline and receives only a `cgo.Handle` userdata token. A shared library loaded by a
  cgo-free process cannot resolve that symbol. The purego ABI must instead receive a callback
  function pointer plus userdata, with a Go registry that does not import `runtime/cgo`.
- `purego.RegisterFunc` cannot verify that a Go signature matches the C symbol, so zigo must generate
  the signatures from `abi.Program` and test every scalar category. Its documented pointer lifetime
  rules still apply, and `NewCallback` slots cannot be reclaimed; generate one dispatcher per
  callback ABI signature rather than one native callback per callback value.
- Shared library discovery is a deployment concern absent from the current API. An absolute Zig
  cache path must never be baked into committed Go. Loading should be atomic, return typed errors,
  allow an explicit path before first use, and use environment/platform names only as documented
  fallbacks.

## Target structure and invariants

- Add `GoBackend = enum { cgo, purego }` to build options. The default remains `.cgo`; invalid
  backend/link-mode combinations fail while constructing the build graph.
- Keep the public generated files backend-neutral. Emit a backend-specific raw file and a small
  backend runtime/loader file; include backend identity in generated-file ownership and reports.
- Resolve every required symbol with `Dlsym` first, bind into local function variables, and publish
  loaded state only after the full symbol set succeeds. A failed load must not leave a partially
  callable package and may be retried with another path.
- Expose a checked, idempotent `LoadLibrary(path string) error` and `LibraryLoaded() bool`. Calls made
  before loading use the same typed library error through a single generated guard. Never call
  `Dlclose` after successful registration.
- For purego callbacks, lower callback parameters to C function pointer plus `uintptr_t` userdata.
  Create one permanent `purego.NewCallback` dispatcher for each unique ABI signature and use a
  synchronized token registry for callback values. Borrowed tokens are deleted after the call;
  retained tokens are deleted by `Close`/cleanup. Recover callback panics and return the existing
  sentinel where the callback ABI supports it.
- Keep the cgo callback ABI and generated public paths compatible unless a separately versioned ABI
  migration is explicitly justified. Backend changes must be visible to ABI report/diff metadata.
