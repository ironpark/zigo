# GOALS

## Problem and the end result from the user's point of view

On Windows, `zig build go` deletes the nested Go files it just published. The
publish step lists what it published from `.zigo-outputs.json`, whose paths are
portable (`event_queue/event_queue_gen.go`), and then walks the Go directory,
whose entries carry the host separator (`event_queue\event_queue_gen.go`). No
walked path matches, so every nested generated file is treated as an obsolete
zigo output and removed; `zigo check` then reports the tree as missing files.
Both Windows CI jobs fail on the generate-and-verify step. The end result is
that generation on Windows leaves the same tree POSIX produces.

## Measurable goals

- `cgo-windows` and `purego-windows` pass on CI.
- Path comparisons between manifest and walked paths ignore the host separator
  and case, and every recorded or reported path is spelled with `/`.

## Supported scope and non-goals

Only the path comparisons that cross the manifest/walker boundary in the
publish step and in `zigo check`. No change to the manifest format, to what is
published, or to generation itself.

## Reference source / commit / license

Introduced by `88f2c429`, released in 0.21.0. CI evidence: run 34197487428.

## Completion criteria for the whole plan

The Windows CI jobs pass on main and a patch release carries the fix.
