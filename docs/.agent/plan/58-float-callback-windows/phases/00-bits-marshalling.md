---
completed_at: "2026-09-01T17:56:19Z"
perf_phase: false
status: done
---
> DONE-WHEN: 08 generates and cross-builds for windows from this host; all local
> NEXT: none

# Uniform bit-marshalled float callback parameters

## Planned Work

- Change purego callback emission: shim invoke `@bitCast`s float params
  to integer bits; header typedefs use the integer types with
  real-type comments; Go dispatchers rebuild floats via
  `math.Float*frombits`; user-facing callback types unchanged.
- Verify and wire the ABI-compatibility recording so the callback ABI
  change is visible to abi-check (stale-library-vs-new-Go mismatch must
  fail loudly); record how in the phase notes.
- Retire or narrow ZIGO014 in `validate.zig` + tests per the analysis;
  windows-target generation of 08-telemetry-hub must succeed.
- Update goldens; regenerate all four purego trees; POSIX suites green;
  `GOOS=windows go vet/build` clean; export-table/cross-build spot
  check for 08's windows DLL using the plan-56/57 procedures.

## Done When

- 08 generates and cross-builds for windows from this host; all local
  suites green; goldens updated; ABI recording decision documented.

## Notes

- Correction to the plan's mechanism: there is no shim-side "invoke
  site" to `@bitCast` at. On the purego backend the exported shim
  function receives the Go dispatcher as a bare C function pointer and
  hands it straight to the target, which stores it and calls it later
  with real floats. Plan 56 recorded the same thing ("a bare C function
  pointer with no room for a stateful adapter"). Converting therefore
  needs the generated trampoline plan 31 removed for this backend, which
  is exactly the breaking change this plan exists to make.
- Shape implemented: for a callback whose parameters include a float the
  shim emits a static thunk with the natural signature and passes that
  to the target. The thunk `@bitCast`s each float and forwards to the Go
  dispatcher, whose address the exported function records in a global
  before the target can reach it. A global is sound here because Go
  builds exactly one dispatcher per callback signature behind a
  `sync.Once`, so every bind stores the same address; the part that does
  vary per callback value, the userdata token, still travels in the
  userdata parameter untouched. The thunk is emitted on every platform,
  so the committed tree stays host- and target-independent. Callbacks
  without floats are still passed straight through.
- ABI recording: the mechanism is the exported symbol name, not
  abi-check. `abi_diff` compares semantic documents, i.e. the user-facing
  API, which this change does not touch. The wire ABI version rides in
  the symbol: `lower.zig` suffixes every callback-carrying purego
  function with the callback convention version. Bumped `_purego_v1` ->
  `_purego_v2` (and `function_pointer_userdata_v1` ->
  `..._v2`, which `zigo-gen report` prints).
- Mismatch demonstrated locally: the stale v1 dylib built from the
  previous commit, loaded by the regenerated Go, panics with
  `resolve "zg_telemetry_hub_create_purego_v2" ...: symbol not found`
  naming the file. It fails at load, before any float is marshalled.
  Note the loader tries the remaining candidates first, so the stale
  library has to be the only one reachable for the failure to surface.
- ZIGO014 narrowed rather than retired, and repointed at a real hole.
  Float *parameters* are no longer a rejection class on any target. But
  since plan 56 made every dispatcher return `uintptr`, a callback
  returning anything other than `void` or `i32` had its result silently
  dropped -- the dispatcher discarded the value and returned 0, and the
  native caller read whatever the register held. ZIGO014 now refuses
  that shape, for the purego backend on every platform rather than for
  windows targets only. This is the "verify and document" item on float
  callback results, resolved by refusing instead of documenting a
  silent corruption.
- `--target-os` removed: with the diagnostic no longer keyed off the
  target, nothing about generation depended on it, and an inert flag
  would misrepresent the generated tree as target-dependent. Dropped
  from `cli.zig`, `generator.Options`, `main.zig`, and `build.zig`.
- Verified: `zig fmt --check`; `zig build check`/`test`; `check` for
  x86_64- and aarch64-windows-gnu; ten cgo trees (`test`, `go-check`,
  `abi-check`, `go`, `go test`); four purego trees
  (`purego-go-verify`, `CGO_ENABLED=0 go vet`/`go test`);
  `GOOS=windows go vet`/`go build` on all four. 08's Windows DLL
  cross-builds from this macOS host and its PE export table lists
  `zg_telemetry_hub_create_purego_v2` (104 exports).
