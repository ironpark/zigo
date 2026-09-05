# SCOPE

- `src/reflect/walk.zig`: read `.iterator` on function entries and `.text` on
  enum type entries; comptime validation of the shapes.
- `src/gen/ir/semantic.zig`: `SemanticFn.iterator`, `TypeDecl.text`.
- `src/gen/validate/functions.zig`, `src/gen/validate/types.zig`: new
  diagnostics `ZIGO050` (iterator shape) and `ZIGO051` (text opt-in on a type
  that is not a registered enum).
- `src/gen/emit/public.zig`, `public_types.zig`, `public_runtime.zig`,
  `references.zig`, `interfaces.zig`: wrapper and text-encoding emission.
- `src/gen/abi_diff.zig`: iterator wrapper and text encoding removal is breaking.
- `src/gen/emit/purego.zig`, `emit.zig`, `cli.zig`, `generator.zig`,
  `src/main.zig`, `tests/generator_case_main.zig`: `--library-platform-dirs`.
- `build.zig`: allow `targets` for purego, per-target library install, doctor
  library selection.
- `tests/generator_cases/*`, `build/tests.zig`, examples, docs, CHANGELOG.

# CONTEXT

## Current implementation and bottlenecks

- `walk.zig` reads function metadata by `@hasField` (`returns`, `release`,
  `cancel`, `constructs`, ...) into `semantic.SemanticFn`; enum entries only
  read `exhaustive`. `semantic.json` serialises with
  `emit_null_optional_fields = false`, so new optional fields cost nothing for
  existing documents.
- `public.zig` renders each public function and, right after its closing brace,
  the `Must` variant via `must.renderMustVariant`; that is the slot for an
  iterator wrapper. `must.writeMustResultType` already spells the payload type
  of an optional return (handle, `Ref`, string, value).
- `public_types.zig` `renderGoEnums` writes the type, constants and `String()`;
  the enums file imports are derived from the body (`public_std_imports`).
- `purego.zig` `renderPuregoCandidates` builds `librarySearchPaths` and
  `resolveSearchPath(entry)`, which joins a directory entry with
  `DefaultLibraryName`. `build.zig` `resolveNativeTargets` panics for purego
  when `targets` is set; the cgo path already installs to
  `library_dir/<goos>_<goarch>/` and retargets the module graph per platform.

## Target structure and invariants

- `.iterator = .{ .name = "All" }` on a function entry. Default name `All`.
  Serialised as `"iterator": {"name": "All"}`. Validation: method with a
  receiver, no Go-visible parameters other than `ctx`, return `?T` or `!?T`.
  Wrapper: `func (r *T) All() iter.Seq2[P, error]` when the method's Go
  signature returns an error, otherwise `iter.Seq[P]`. The wrapper calls the
  public method, stops on `ok == false`, and yields `(zero, err)` once then
  stops on error. Two iterators with the same name on one type are a name
  clash diagnostic like any duplicate Go name.
- `.text = true` on an `.enumeration` entry. Serialised as `"text": true`.
  Generates `Parse<Enum>(text string) (<Enum>, error)`,
  `func (v <Enum>) MarshalText() ([]byte, error)` (never fails; unknown values
  of open enums marshal as `String()`), and
  `func (v *<Enum>) UnmarshalText(text []byte) error`. Open enums also parse
  the `<Enum>(N)` spelling. Failures return `*EnumParseError{Type, Text}`
  emitted as a gated runtime helper.
- purego `targets`: `resolveNativeTargets` accepts purego, every entry installs
  to `library_dir/<goos>_<goarch>/`; `build.zig` passes
  `--library-platform-dirs` to the generator, whose loader joins
  `runtime.GOOS + "_" + runtime.GOARCH` between a directory entry and the
  library name in `resolveSearchPath`. Explicit `LoadLibrary(path)` and
  environment-variable values stay verbatim. Doctor gets `--library` from the
  first host-runnable target. Without `targets` nothing changes.
