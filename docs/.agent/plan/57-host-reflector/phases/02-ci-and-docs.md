---
depends_on:
- "57-host-reflector#1"
perf_phase: false
status: in-progress
---
> DONE-WHEN: CI green on both runners with the artifact leg exercising the
> NEXT: none

# Cross-build CI leg and docs

## Planned Work

- Ubuntu CI job: add a step cross-building 07-event-queue's Windows DLL
  and uploading it as an artifact; Windows job: download it and run the
  07 suite against it via `ZIGO_TEST_LIBRARY` in addition to its native
  legs.
- Update docs: cross-compile recipe (`zig build go-lib -Dtarget=...` per
  OS), remove the plan-56 "cross-compilation unsupported" limitation,
  document the host-reflection semantics (target-conditional surfaces
  unsupported; layout divergence caught at target compile time by the
  guards).

## Done When

- CI green on both runners with the artifact leg exercising the
  cross-built DLL; docs updated; no stale limitation text;
  `planr overview` shows the plan done.

## Notes

- CI, Ubuntu `purego` job: after the artifact inspection it cross-builds
  `examples/07-event-queue` with `zig build purego-go-lib
  -Dtarget=x86_64-windows-gnu` and uploads `event_queue_zigo.dll`
  (`if-no-files-found: error`, so a silently missing DLL fails the job). The
  step writes only into `zig-out`, which is gitignored, so the drift check
  ahead of it is unaffected and no artifact needs restoring.
- Two deviations from the planned shape, both deliberate:
  - The runtime leg is a new `purego-windows-cross` job with `needs: purego`
    rather than extra steps inside `purego-windows`. Adding them to the
    existing job would have made every native Windows leg wait on the whole
    Ubuntu purego job. The new job needs no Zig and no generation -- only Go
    and the committed bindings -- so it is short.
  - It sets `ZIGO_LIBRARY_PATH`, not `ZIGO_TEST_LIBRARY`. 07's suite already
    honours `ZIGO_LIBRARY_PATH` in its `init`, and loads the whole suite
    (callbacks included) through it; `ZIGO_TEST_LIBRARY` is 10-tagged-union's
    own opt-in variable. Using the existing hook meant touching no test code.
- Doctor repair the gate removal exposed, found by running
  `zig build purego-go-doctor -Dtarget=x86_64-windows-gnu`: it printed
  `FAIL target: cross compilation is not supported` and
  `FAIL shared library: ... .dll is missing`, both now false for purego.
  - `render` reports `SKIP target: cross build; ...` for a purego cross build
    and keeps `FAIL` for cgo, whose cross-link story is genuinely unverified.
  - `build.zig` stops passing `--library` when the target is not host-runnable,
    and the doctor prints `SKIP shared library: a cross-built artifact cannot
    be loaded on this host`. Neither SKIP makes the doctor unhealthy, so
    `zig build purego-go-verify -Dtarget=x86_64-windows-gnu` is now green --
    verified locally. A new unit test pins that pair.
  - Known cosmetic gap, not fixed: `PASS purego platform: macos/aarch64 is
    supported` still names the host in a cross run. The sentence is true as
    written, and reporting the target would mean plumbing the triple through
    the doctor CLI for no behavioural gain.
- Docs: `docs/limitations.md` loses the "reflector runs, so v1 cannot cross
  compile" bullet and the "Windows DLL은 Windows 호스트에서" claim; both are
  replaced by the supported recipe plus the two consequences of host-side
  reflection (layout divergence caught by the guards, target-conditional
  binding surfaces unsupported). `docs/purego.md` gains the multi-target
  `-Dtarget` recipe, the `zigo ABI guard` failure text, the doctor SKIP
  behaviour and a pointer at the CI artifact leg; its opening callout and the
  backend table no longer say the library must be built on a native host.
- Green locally: `zig fmt --check`, `zig build check` (native, x86_64- and
  aarch64-windows-gnu), `zig build test`, ten cgo trees and their Go suites,
  four purego trees and their `CGO_ENABLED=0` Go suites, no example drift.
  Windows runtime proof is CI's, and is not claimed here until it passes.
