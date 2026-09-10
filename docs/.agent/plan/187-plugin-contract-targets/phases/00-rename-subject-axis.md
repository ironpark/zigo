---
completed_at: "2026-09-10T03:32:13Z"
perf_phase: false
status: done
---
> DONE-WHEN: `grep -rn 'Target' src/plugin.zig` matches only `targets.Target`, the output
> NEXT: none

# Free the word "target" inside the contract

## Planned Work

- Rename `plugin.Target` to `plugin.Subject`, `plugin.typeTarget` to
  `plugin.typeSubject`, `Plugin.targets` to `Plugin.subjects`, and the
  `supports(target: ?Target)` parameter to `subject`.
- Follow it into the authoring surface that mirrors the field:
  `src/features.zig`'s local `Target` enum and its three `.targets` literals,
  the `P.targets` walks in `src/declare.zig` and `src/author.zig`, and the
  inline plugin literals in `src/context_tests.zig`, `src/reflect/walk.zig` and
  `src/author.zig` tests.
- Follow it into every plugin: `plugins/satisfies`, `plugins/json`,
  `plugins/enumkit`, the five under `src/gen/plugins/`, the four under
  `tests/plugins/`.
- Update `docs/plugins/api-reference.md` and `docs/plugins/authoring.md`.
- Rename the two `binding_errors` fixtures that test this axis --
  `plugin_target.zig` and `unsupported_plugin_target.zig` -- to `plugin_subject`
  and `unsupported_plugin_subject`, with their entries in `build/tests.zig`.
  Their expected compile-error text does not contain the field name, so it is
  unchanged.
- Nothing else moves. No target is threaded yet and no output file is renamed.

## Done When

- `src/plugin.zig` no longer uses `Target` for the declaration-kind axis. It
  still uses it for the *build platform* -- `CgoTarget`, `TargetLdflags`,
  `cgo_targets`, `target_ldflags`, which hold `goos`/`goarch`. That is a third
  meaning, and it stays: it is the industry-standard sense of the word, it is
  unambiguous where it appears, and `cgo_targets` is user-facing build
  integration. The declaration-kind sense was the idiosyncratic one, and it is
  the one this phase removes.
- `Plugin` declares `subjects` and no `targets`.
- `zig build test --summary all` passes and
  `git status --short tests examples` is clean: a rename cannot move output.
