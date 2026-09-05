# SCOPE

- `src/gen/emit/emit.zig`, `raw.zig`: `cgo_targets` option and qualified
  directive emission.
- `src/gen/cli.zig`, `src/main.zig`, `src/gen/generator.zig`,
  `tests/generator_case_main.zig`: plumb `--cgo-target goos/goarch`.
- `src/build_options.zig`: Zig target to GOOS/GOARCH mapping and the target
  directory name.
- `build.zig`, `build/steps.zig`: `Options.targets`, per-target module
  retargeting, per-target library/implib install, per-target volatile link
  flags, doctor target selection, `GoBindings` per-target install handles.
- `tests/generator_cases/scalar_multi_target`, `build/tests.zig`.
- Docs, README, CHANGELOG.

# CONTEXT

## Current implementation and bottlenecks

- `raw.zig` `renderRaw` writes one `#cgo LDFLAGS:` line from `library_dir`,
  `library_stem` and `link_mode`; only the darwin framework line is qualified.
- `build.zig` `addGoBindings` builds one `lib` for `options.target`, renames a
  Windows static archive to `lib<stem>.a` so the emitted line is identical on
  every host, and installs into one `install.library_dir`.
- `PublishCgoLinkFlags` writes the volatile `zigo_link_inputs_gen.go` with one
  unqualified line for static link inputs built for the one target.
- `hostReflectionModule` already clones a module graph for another target
  (the host); it is the pattern for retargeting per listed target.
- Doctor receives `--target native|cross` from a single comparison.

## Target structure and invariants

- `emit.Options.cgo_targets: []const CgoTarget` where `CgoTarget = { goos,
  goarch }`. Empty keeps today's single line. Non-empty emits, per target,
  `#cgo <goos>,<goarch> LDFLAGS: <library_dir>/<goos>_<goarch>/lib<stem>.a`
  (or `-L<dir>/<goos>_<goarch> -l<stem>`) followed by the same extra and
  system flags. `ldflags_override` still wins and stays unqualified.
- `build_options.goTarget(std.Target) ?GoTarget` maps `os.tag`/`cpu.arch` to
  GOOS/GOARCH; unsupported combinations panic at configure time.
- Per-target archives install to `<library_dir>/<goos>_<goarch>/`. The
  Windows static rename applies per target as before.
- The generated Go tree is still produced once; only native builds repeat.
- The volatile file emits one qualified line per target when static link
  inputs exist, with that target's rebuilt archives installed in its subdir.
