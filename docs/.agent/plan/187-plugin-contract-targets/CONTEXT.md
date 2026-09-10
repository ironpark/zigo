# SCOPE

Changed: `src/plugin.zig` and `src/plugin/{interfaces,rename,site}.zig`; the
declaration-kind axis in `src/declare.zig`, `src/author.zig`,
`src/features.zig`, `src/context_tests.zig` and `src/gen/validate/validate.zig`;
the `ZIGO059` rule and `PreparedFile` bookkeeping in `src/gen/generator.zig`;
`src/gen/targets.zig` and `src/gen/targets/go.zig` for the file-shape members
the rule needs; every plugin under `src/gen/plugins/`, `plugins/` and
`tests/plugins/`; `docs/plugins/api-reference.md` and
`docs/plugins/authoring.md`; `CHANGELOG.md`.

Untouched: `src/gen/emit/**`, `src/gen/ir/**`, `src/reflect/**`,
`src/gen/naming.zig`, `src/gen/sync_check.zig`, and every generated file.

# CONTEXT

## Current implementation and bottlenecks

The contract has three layers that this plan has to treat differently, because
only two of them are actually language-neutral.

**Framing.** `OutputScope`, `GoPackage`, `GoFileKind`, `GoFile`, `Artifact`,
`goFilePathAlloc`, `publicFilePathAlloc`, the enable predicate, ordering and
config. All of it describes *where a generated file goes and when it is
written*, which no output language changes. It is Go-named and nothing more.

**Identity.** `FunctionInfo.go_name`, `Method.go_name` and `writeDoc`'s
`go_name` parameter all mean "the name this declaration has in the public API".
Plan 186 already moved the rule that computes it onto `Target`
(`publicFunctionNameAlloc`), so the contract is carrying a Go-named field whose
value a target now produces.

**Syntax.** `Context.writeGoType` and its five siblings write Go source into a
`std.Io.Writer`. These are not neutral and cannot be made neutral by renaming:
there is one emitter, `src/gen/emit/**`, which plan 186 deliberately placed
*behind* the target seam because the research measured its Rust reuse at zero.

The consequence of not separating the three is `ZIGO059`. It checks that a
plugin's file lands in the right directory with the right extension and the
right test suffix, and it does so with `std.mem.endsWith(u8, normalized, ".go")`
and `"_test.go"` written into `src/gen/generator.zig`. `Target` already carries
`source_extension`; it does not yet carry the test-file rule, because until now
nothing asked.

`plugin.Target` is the second bottleneck and the reason phase 0 exists. It is
the declaration-kind enum, and `Plugin.targets` is how an external plugin
declares which kinds it attaches to -- shipped surface, written in
`plugins/satisfies/src/plugin.zig` as `.targets = &.{ .handle, .value,
.enumeration, .tagged_union }`. Plan 186 already had to rename its own module
from `target` to `targets` because `const target = @import("target")` shadowed
locals in three files. The word cannot carry both meanings.

## Target structure and invariants

- `Plugin.subjects: []const Subject` replaces `Plugin.targets`, and
  `Plugin.output_targets: []const []const u8 = &.{"go"}` is new. Two axes, two
  names, neither of them ambiguous.
- A plugin is skipped entirely -- validation hooks, transforms, outputs -- when
  the resolved target's `name` is not in its `output_targets`. This is what lets
  the Go syntax writers stay Go's without lying: a plugin that calls them says
  so in one field.
- `Target` gains the file-shape members `ZIGO059` needs. Go answers
  `source_extension = ".go"` and a test-file rule of `_test.go`; the members are
  shaped so a language whose tests are not a filename convention can answer
  "none" rather than being forced into Go's shape.
- Every context that a plugin sees exposes the resolved target, so a plugin and
  the generator agree on one value rather than both reaching for
  `targets.default`.
- The contract is a compile-time contract: `min_contract` already exists and
  plugins pin it. Bumping to 3.0 is therefore a clean break with no shim, which
  is what 2.0 did before it and what `CHANGELOG.md` records as a minor-version
  event during 0.x.
