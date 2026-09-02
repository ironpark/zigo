# GOALS

## Problem and the end result from the user's point of view

Two smaller ergonomics items. First, naming diagnostics (ZIGO021 emitted-name check, ZIGO024 Go name collision, ZIGO036 C identifier collision) say what collided but not how to fix it; a `note:` line with a concrete suggestion (`consider .name = "SearchSelectKind" on type SearchSelect`) ends the investigation immediately. Second, callback metadata cannot state when a callback runs or whether it may re-enter the receiver; that contract lives in comments. The end result: diagnostics carry an optional `note`, and `param_meta.callback` accepts `.reentrancy = .allowed | .forbidden` and `.thread = .caller | .any`, rendered into the generated Go doc comment of the parameter's callback type and the function.

## Measurable goals

- `diagnostic.Diagnostic` gains `note: ?[]const u8` rendered as `  note: ...` after `hint`; ZIGO021, ZIGO024, ZIGO036 (and ZIGO009 retention) populate it with a concrete, syntactically valid suggestion derived from the colliding names (a `.name` for the declaration that is cheaper to rename: prefer types over functions, never suggest renaming a constructor).
- Snapshot tests in `validate.zig` updated; `docs/limitations.md` diagnostics section mentions notes.
- Callback contract metadata reflected into semantic.json (`callback.reentrancy`, `callback.thread`), validated (only on callback params), and emitted into Go doc comments on both backends; no runtime behaviour change in this plan (thread pinning is a documented non-goal).
- Docs `bindings.md` "콜백" section and CHANGELOG.

## Supported scope and non-goals

In scope: `diagnostic.zig`, `validate.zig`, `walk.zig` callback metadata, `semantic.zig`, emit doc comments, docs.
Non-goals: `runtime.LockOSThread` handling; changing any diagnostic code or message text beyond adding the note.

## Reference source / commit / license

Current main; `src/gen/diagnostic.zig` render format.

## Completion criteria for the whole plan

Both phases done; verification loop green; docs and CHANGELOG updated; tree clean.
