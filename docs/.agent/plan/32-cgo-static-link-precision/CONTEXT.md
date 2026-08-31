# SCOPE

This plan changes the generated cgo LDFLAGS, the generator CLI and emitter options that carry the
link mode, every committed cgo raw file and golden fixture, one CI job, and the wiki sections that
describe verifying both backends. Semantic IR, the public Go API, and the purego backend are
unchanged.

# CONTEXT

## Current implementation and bottlenecks

- `emit.renderCgoRaw` writes `-L{library_dir} -l{package}_zigo` whenever no `cgo_flags` override is
  set. The emitter has no link-mode information, so it cannot tell a static from a dynamic build.
- `build.zig` already passes `--library-stem` for the purego loader, which gives the emitter the
  artifact base name it needs for an explicit archive path.
- Both binding sets of an example install into the same `zig-out/lib`, so the collision appears as
  soon as a user builds both backends, which the new purego documentation tells them to do.
- `zig build go-check` compares generated text, so any LDFLAGS change requires regenerating the ten
  examples and the two generator-case fixtures in the same commit.

## Target structure and invariants

- Add the link mode to the generate CLI, generator options, and emitter options, defaulting to
  static so existing callers keep their behavior.
- For static links emit `{library_dir}/lib{stem}.a`; for dynamic links keep the search-path form,
  which is what a dynamic cgo build wants. System and framework flags keep their current position.
- The archive basename is the same on macOS and Linux, so the generated text stays identical across
  supported hosts.
- An explicit `cgo_flags` override still wins over both forms.
