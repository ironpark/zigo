---
depends_on:
- "49-49-skip-empty-generated-go#1"
perf_phase: false
status: planned
---
> DONE-WHEN: `zig build go` and `zig build go-check` pass in every example directory.
> NEXT: none

# Publishing copies whatever generation produced

## Planned Work

- Replace the five `addCopyFileToSource` calls for Go files in `build.zig:716`
  with a step that walks the generated directory at make time and copies every
  `.go` file to the same relative path under `options.go_dir`. The explicit
  copies for `errors.lock.json` and `zigo/semantic.json` stay as they are: those
  paths are fixed and go somewhere else.
- The step prunes as well as copies: a `.go` file under `options.go_dir` that
  carries the generated marker and has no counterpart in the generated tree is
  deleted. Without this, shrinking the file set leaves a stale file that
  `zigo check` immediately reports as obsolete.
- Report copies and deletions the way `UpdateSourceFiles` does, so a build that
  rewrites the source tree still says so.
- Regenerate every example and delete the nine empty files under `examples/`.

## Done When

- `zig build go` and `zig build go-check` pass in every example directory.
- `git ls-files '*_gen.go'` lists no two-line file.
- Deleting a generated Go file by hand and re-running `zig build go` restores
  it; adding a spurious `*_gen.go` with the generated marker and re-running
  removes it.
- Apart from the nine deletions, no committed example artifact changes.
