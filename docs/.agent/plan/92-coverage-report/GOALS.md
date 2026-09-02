# GOALS

## Problem and the end result from the user's point of view

Binding projects repeatedly ask "what upstream API is not bound yet" and answer it by grepping upstream sources. zigo already reflects the whole root module, so it can report the unbound public declarations. The end result: `zig build go-coverage` prints a summary and a per-declaration list with a best-effort reason, and optionally writes it as JSON next to the other generated artifacts.

```
gostty: 100/147 public declarations bound (68%)
  unbound: Terminal.dumpString  (reason: writer param, no metadata)
  unbound: Screen.pages         (reason: no C representation)
```

## Measurable goals

- The reflect executable gains a coverage mode that walks `root` (recursively through containers, same rules as `.discover = .recursive`) and every registered type, classifying each `pub fn` as bound, excluded (`exclude`), or unbound with a reason drawn from the existing type-offense classifier (`typeOffense`/ZIGO reasons) or "not listed" when it would bind if listed.
- `pub` types (structs, enums, unions) that are referenced by bound or unbound functions but not registered are listed under "unregistered types".
- Output: text to stdout by default; `-Dcoverage-json=<path>` or a build option writes JSON; the build helper exposes `go-coverage` alongside `go-check`.
- Docs in `docs/configuration.md` and `docs/development.md`; CHANGELOG; a unit test for the classifier and an example step wired in at least one example.

## Supported scope and non-goals

In scope: `src/reflect/walk.zig`/`main.zig`, `build.zig` step wiring, `src/gen/report.zig` or a new `coverage.zig`, docs.
Non-goals: exact reasons for every rejection (best effort is acceptable; unknown reasons print "unsupported signature"); coverage of fields (until field accessors exist).

## Reference source / commit / license

Current main; discovery code in `walk.zig`; `doctor.zig` for how a diagnostic-style report is rendered.

## Completion criteria for the whole plan

Phase done; verification loop green; docs and CHANGELOG updated; tree clean.
