# GOALS

## Problem and the end result from the user's point of view

Generation must never expose a partially rendered artifact set after a semantic,
rendering, or allocation failure. The stable error-code lock must reject malformed
or incompatible state, and best-effort reflection enrichment must explain why it
fell back. A complex golden case must keep these combined contracts visible.

## Measurable goals

- Render and validate every generated artifact before mutating the output tree.
- Reject unsupported lock versions, altered reserved codes, reused mappings, and
  unsafe append-only transitions with focused tests.
- Report the source path and failure reason for reflection enrichment failures.
- Add a multi-feature golden generator case covering errors, slices, enums,
  opaque handles, callbacks, ownership metadata, and colocated/custom output.

## Supported scope and non-goals

This plan covers the generator transaction boundary, errors.lock parsing and
transition validation, reflection name/doc enrichment diagnostics, generator
goldens, and corresponding documentation. It does not promise recovery from a
machine or filesystem failure during the final file commit and does not change
the public Go API model.

## Reference source / commit / license

The implementation is based on this repository at the current branch head and
the installed Zig 0.16.0 standard library. No external source is copied.

## Completion criteria for the whole plan

All focused allocation/error tests, generator golden cases, the complete Zig test
graph, formatting checks, representative Go tests, and the Windows compile check
pass with documented failure semantics.
