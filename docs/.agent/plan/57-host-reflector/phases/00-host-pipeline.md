---
completed_at: "2026-09-01T16:51:14Z"
perf_phase: false
status: done
---
> DONE-WHEN: Cross go-lib builds succeed from POSIX for supported targets; no
> NEXT: none

# Host-built reflection pipeline

## Planned Work

- Retarget `semantic_module`, `bindings_module`, and the `zigo-reflect`
  executable to `b.graph.host` in `addGoBindings`; remove the purego
  `isRunnableOnHost` panic and its comment; keep the doctor cross wiring.
- Verify from this POSIX host: `zig build go-lib
  -Dtarget=x86_64-windows` (and one linux cross target) succeeds for a
  Windows-eligible example (07 or 10); list the cross-built DLL's export
  table with the plan-56 procedure and confirm it matches the native
  expectation; confirm `go-check` shows zero generated-Go drift after a
  cross-targeted generation run.
- Confirm ZIGO014 still fires for 08-telemetry-hub with
  `-Dtarget=x86_64-windows` (target-driven, not host-driven).

## Done When

- Cross go-lib builds succeed from POSIX for supported targets; no
  generated-Go drift; export table verified; `zig build test`/`check`
  (native + windows cross-check) green; all local suites pass.

## Notes

- The three reflection modules (`semantic_module`, `bindings_module`, the
  `zigo-reflect` executable) now build for `b.graph.host`; the shim module,
  library, and header install stay on `options.target`. The user's module is
  imported by both, so it compiles twice -- exactly as `zigo-gen` already did.
  The purego `isRunnableOnHost` panic is gone; `puregoTargetSupported` still
  gates the target, and `isRunnableOnHost` survives only for the doctor's
  `--target native|cross` flag.
- Cross-builds verified from macOS/aarch64 for 07-event-queue's purego
  library: `x86_64-windows`, `x86_64-windows-gnu`, `aarch64-windows-gnu`
  (all produce `zig-out/bin/event_queue_zigo.dll`) and `x86_64-linux-gnu`
  (`libevent_queue_zigo.so`).
- Export table of the cross-built DLL, listed by parsing the PE export
  directory directly (Zig 0.16 ships no binutils): 32 names for both the msvc
  and gnu ABI builds. All 16 symbols the generated Go loader resolves are
  present -- 16/16, matching the audit plan 56 phase 6 recorded. Note the
  earlier r2o pitfall: map RVAs with a strict `va <= rva < va + virtual_size`
  section lookup, or `.text` swallows the `.rdata` export directory.
- Zero generated-Go drift: `zig build purego-go -Dtarget=x86_64-windows-gnu`
  in 07-event-queue left `git status -- examples` empty, so the committed tree
  is byte-identical whether generation ran natively or while cross-targeting.
- ZIGO014 still fires for 08-telemetry-hub under
  `-Dtarget=x86_64-windows-gnu` and still does not fire natively: the
  rejection is driven by `--target-os`, which stays on `options.target`.
- Suites green: `zig fmt --check`, `zig build check` (native, x86_64- and
  aarch64-windows-gnu), `zig build test`, ten cgo example trees
  (`test`/`go-check abi-check`/`go`), four purego trees
  (`purego-go purego-go-verify`) and their `CGO_ENABLED=0` Go suites.
- Not yet safe to advertise: reflection now records *host* layouts into
  `semantic.json`. Phase 1 adds the comptime ABI guards that make a divergent
  target fail loudly instead of silently mismatching.
