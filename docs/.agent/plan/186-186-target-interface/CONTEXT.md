# SCOPE

Added: `src/gen/target.zig` (the interface, the formatter record, the target
list) and `src/gen/target/go.zig` (Go's answers).

Changed: `src/gen/naming.zig` (Go rules removed), `src/gen/ir/semantic.zig`
(`publicFunctionNameAlloc` removed), their callers in `src/gen/validate/**`,
`src/gen/emit/**`, `src/gen/abi_diff.zig`, `src/gen/report.zig`,
`src/gen/generator.zig`, `src/plugin/interfaces.zig`, `src/reflect/packages.zig`,
`src/reflect/walk.zig`, `src/main.zig`, and the module graphs in `build.zig`,
`build/modules.zig` and `build/tests.zig`.

Untouched: `src/gen/emit/shim.zig`, `header.zig` and `target_types.zig` (the C
pivot), `src/declare.zig`, `src/author.zig`, `src/root.zig`, `src/plugin.zig`'s
contract types, `plugins/**` and `tests/plugins/**` (they call only
`pascalAlloc`, which stays), and every generated artifact.

# CONTEXT

## Current implementation and bottlenecks

`naming.zig` is a leaf module imported by nine other modules, including the
`zigo` module a consumer's build compiles. That is why the Go rules ended up
there: it was the only place every layer could already reach. It carries five
plainly Go-named `pub fn`s -- `isGoKeyword`, `isGoIdentifier`,
`validateGoPackageName`, `goParamNamesAlloc`, `libraryPathEnvironmentAlloc` --
and three more that are Go rules without saying so: `ownerPascalAlloc` ("the Go
spelling of an owner path"), `variantTypeNameAlloc` (a Go type name plus a
clash-resolution suffix) and `unionFileStemAlloc` (a stem for
`<pkg>_union_<stem>_gen.go`).

Two of those predicates have been copied rather than imported:
`src/gen/validate/types.zig:1536` and `src/gen/validate/functions.zig:502`
each declare a private `isGoIdentifier`. That is the drift this plan removes.

`semantic.publicFunctionNameAlloc` has twelve callers and is the single rule
for a public Go name: the `go.name` override first, then the paired
constructor, then `pascalAlloc`. Both of its first two steps read the `go`
namespace plan 185 created, so it is per-target by construction, and it cannot
take a `Target` where it is: `semantic` is imported by `target` would be a
cycle. It moves to `target.zig`.

`formatGeneratedGo` in `src/main.zig:110-145` knows four things about gofmt at
once: the executable name, that `-w` writes in place, that `--gofmt <path>`
overrides it, and that a Go distribution is what to install. It selects files
by `manifest.file.kind == .go`, and `src/gen/generator.zig:202` assigns that
kind by testing for a `.go` suffix.

## Target structure and invariants

`src/gen/target.zig`:

```zig
pub const Target = struct {
    name: []const u8,               // "go"
    source_extension: []const u8,   // ".go"
    generated_suffix: []const u8,   // "_gen"
    formatter: ?Formatter,
    vtable: *const VTable,
    // forwarders: isKeyword, isIdentifier, validatePackageName,
    // paramNamesAlloc, exportedNameAlloc, unexportedNameAlloc, stemAlloc,
    // ownerNameAlloc, variantTypeNameAlloc, unionFileStemAlloc,
    // libraryPathEnvironmentAlloc, publicFunctionNameAlloc,
    // generatedFileNameAlloc, isGeneratedSource
};

pub const Formatter = struct {
    default_executable: []const u8,   // "gofmt"
    leading_args: []const []const u8, // .{"-w"}
    override_flag: []const u8,        // "--gofmt <path>"
    install_hint: []const u8,         // "install the Go distribution"
};

pub const go: Target = @import("target/go.zig").target;
pub const all: []const Target = &.{go};
pub const default: Target = go;      // the target a build that names none gets
pub fn byName(name: []const u8) ?Target;
```

Invariants:

- The `target` module imports `naming` and `semantic` and nothing else from the
  generator. `semantic` must never import `target`: the IR does not know the
  output language, which is the decision plan 185 established.
- `Target` is a value, not a comptime global. Layers that a second target
  reuses receive it; they never reach for `target.go` or `target.default`.
- The seam runs between the target-agnostic layers and the target's emitter.
  `src/gen/emit/**` is Go's emitter, so it may call `target/go.zig` helpers
  directly; it is behind the seam, not in front of it.
- `Target` stops above the C ABI. No shim, header, C name or `isCKeyword`
  caller learns about it, because `Zig -> semantic IR -> shim + C header` is
  target-independent and is the pivot a second target reuses whole.
- Every step is byte-identical output. A moved rule keeps its body; if any
  snapshot moves, the move was wrong.
