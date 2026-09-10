# SCOPE

- `src/gen/emit_rust/raw.zig`, `public.zig`, `types.zig`
- `src/gen/targets.zig`, `src/gen/targets/rust.zig`, `src/gen/targets/go.zig`
- `src/gen/naming.zig`
- `src/gen/generator.zig`
- `src/gen/validate/validate.zig`
- `build.zig`
- `tests/generator_cases/rust_slice_return/` (new)

# CONTEXT

## Current implementation and bottlenecks

`Shape` in `emit_rust/raw.zig` is the single description both wrappers derive
from. It carries three fields that are not independent: `Input.source_index` is
always the input's own index, so `inputFor` is a linear scan for the identity
mapping; `Input.text` is a copy of `Input.element.?.text`; and
`writeRawPointee` takes an `is_many` it discards. `types.sliceElement` and
`elementScalar` thread a `program` neither uses -- the tell that `elementScalar`
was copied from `emit/type_spelling.zig`'s `semanticScalar` and stripped.

`renderRaw`, `renderExternBlock` and `renderLib` each skip a function when
`types.unsupported` is non-null. None of the three can fire: `appendRustCrate`
calls `emit_rust.unsupportedIssues` and returns `error.InvalidSemantic` before
any emitter runs. The guards make the emitters read as a filtering pass, which
is the silent-omission behaviour the ZIGO060 design note exists to prevent.

`public.zig`'s slice-payload branch copies twice: `.to_vec()` allocates and
copies, then `String::from_utf8_lossy(&result).into_owned()` allocates and
copies again because `from_utf8_lossy` returns `Cow::Borrowed` for valid UTF-8.
The non-text arm emits `let result = result;`, which clippy's `redundant_locals`
would reject. Neither is caught, because no generator case binds a slice
*return* -- `rust_slice` covers slice parameters only -- so the golden
`rustc -D warnings` step never compiles this path.

`targets/rust.zig` copies Go's `libraryPathEnvironmentAlloc` verbatim; its own
doc comment claims the rule is "reused rather than reinvented" and a test
asserts the two agree, but nothing makes them agree. It also declares
`generatedFileNameAlloc` and `publicFunctionNameAlloc` wrappers "for callers
already inside the Rust emitter" that have no caller, and lists `handle` among
the locals a parameter must not shadow, which the Rust bodies never bind.

`generator.zig:178` selects the backend by comparing `Target.name` against
Rust's, with Go as the `else`. A third target added to `targets.all` compiles,
resolves, and silently emits Go. The refusal step lives in `appendRustCrate`'s
body rather than beside the dispatch, so a third backend reinvents it; and
`appendRustCrate` never calls `appendArtifacts`, so a plugin declaring
`output_targets = &.{"rust"}` has its hooks run and its artifacts dropped with
no message.

`validate.zig:218` writes a plugin's `name_function` result with `setGoName`
while `target` is in scope on the enclosing line. The branch built the read
side of that seam (`Target.nameOverride`, `FnRust.name`, `setRustName`) and
left the write side hardcoded.

`addRustBindings` copies three post-reflection blocks out of `addGoBindings`
verbatim: the errors-lock probe, the staleness check wiring and the abi-check
baseline. All three operate on `semantic.json` and `errors.lock.json`, which
the seam argument says every target shares.

## Target structure and invariants

- A field exists only if no other field answers it.
- A guard exists only if it can fire.
- A rule that two targets must agree on has one definition; agreement is
  structural, not asserted by a test.
- Backend selection is table-driven over `targets.all`, with no default
  language.
- Every generated code path a target can reach is compiled by a golden.
