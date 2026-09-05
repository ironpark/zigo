---
perf_phase: false
status: planned
---
> DONE-WHEN: `zig build test --summary all` passes.
> NEXT: none

# purego targets

## Planned Work

- `emit.Options.library_platform_dirs` and CLI `--library-platform-dirs`;
  `renderPuregoCandidates` joins the platform subdirectory in
  `resolveSearchPath`; `report` shows the policy.
- `build.zig`: `resolveNativeTargets` accepts purego; pass the flag when
  `targets` is set; doctor picks the host-runnable library; keep the cgo
  constraint machinery untouched for purego entries.
- Generator case `scalar_multi_target_purego`.
- Build-level check in `build/tests.zig` or a manual smoke described in the
  plan verification: two purego targets install side by side.
- Docs: `purego.md` cross-compile section, `configuration.md` targets section,
  `limitations.md`, README backend table, CHANGELOG.

## Done When

- `zig build test --summary all` passes.
- A temporary purego project with two targets installs both libraries under
  platform subdirectories and the host `go test` loads the host one through
  the default search path.
