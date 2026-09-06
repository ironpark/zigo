# GOALS

## Problem and the end result from the user's point of view

Three kinds of repetition and one wrong answer, all found by reading a real
binding (libghostty-vt) rather than the test suite.

- `.semantic = .utf8_string` is written at more than twenty positions. Every
  `[]const u8` in that library is text; the one exception is a clipboard
  payload. The binding spends a line per position saying what the default
  should have said.
- `.returns = .caller, .release = "root.freeString", .semantic = .utf8_string`
  appears five times verbatim. The release function is a property of the
  binding, not of each function.
- The callback contract block (`retention`, `reentrancy`, `thread`) is copied
  at four call sites. It describes `ClipboardFn` and `SysFn`, which are
  registered callback types, so it belongs on the type entry. Copies drift:
  one site left at `.borrowed` is a silent lifetime bug.
- Parameter names and docs are wrong or missing for declarations zigo cannot
  see. Enrichment reads the bindings file, its direct imports and `root.zig`'s
  imports; a dependency module's sources are never read, so
  `Terminal.setCursorStyle` takes `p0`. Worse, the unqualified fallback match
  in `names.zig` pairs a declaration with any function of the same Go name and
  arity, so `Search.feed` (bound from `root.searchFeed`) took its parameter
  name from `Stream.feed` in another file and became `Feed(bytes bool)`.

Afterwards: `.strings = .infer_utf8` and `.string_release` remove the first two
repetitions, a `.repr = .callback` entry carries the contract its call sites
inherit, and enrichment matches the declaration the binding actually named --
scanning the bound module's dependencies so the names exist to be matched.

## Measurable goals

- The libghostty-vt binding can drop every `.semantic = .utf8_string`, keep
  only the `.opaque_bytes` exception, drop four `.release`/`.semantic` pairs,
  and drop three-line contract blocks at four call sites.
- No parameter of that binding is named `p0`, and no parameter name comes from
  a declaration the binding did not name.
- Existing goldens are unchanged except where a case opts into a new default.

## Supported scope and non-goals

In scope: define-level `.strings`, define-level `.string_release`, contract
defaults on `.repr = .callback` entries, correct declaration matching in
`reflect/names.zig`, and reaching dependency-module sources for enrichment.

Out of scope: inferring `.opaque_bytes`, a per-type string release, changing
what a hint means once resolved, and any change to the C ABI.

## Reference source / commit / license

None; zigo's own surface. The motivating consumer is the gostty binding.

## Completion criteria for the whole plan

`zig build test --summary all` passes, generator goldens are unchanged except
for new cases, the docs describe each default and its opt-out, and the
enrichment fix has a regression test with two same-named declarations in
different files.
