# SCOPE

- `src/gen/generator.zig` — the skip decision and the removal.
- `src/main.zig`, `src/gen/cli.zig` — generation formats its own Go output.
- `build.zig` — the generated Go file set stops being a configure-time list.
- `examples/*/go*/**` and `tests/generator_cases/*/expected/**` — the deleted
  artifacts.

# CONTEXT

## Current implementation and bottlenecks

`generator.zig` renders every entry of `emit.all` into `prepared` and then
writes each one. Nothing consults the rendered content.

The three emitters that can come out empty already know they are empty:
`renderPublicHelpers` returns early when there are no callbacks and no bool
helper, and `renderPublicTypes` and `renderPublicErrors` guard every section.
Each writes the two prelude lines before reaching that point, so "nothing to
declare" is already expressed — as a file whose body ends after the `package`
line.

The affected files today:

    examples/01-scalar/go/scalar/{scalar_errors,scalar_helpers,scalar_type}_gen.go
    examples/02-errors/go/errors/errors_helpers_gen.go
    examples/03-opaque/go/opaque/opaque_helpers_gen.go
    examples/06-camel-case/go/http_client/{..._errors,..._helpers,..._type}_gen.go
    examples/09-type-relations/go/type_relations/type_relations_helpers_gen.go
    tests/generator_cases/scalar/expected/scalar/{...errors,...helpers,...type}_gen.go

`generate` writes straight into the user's Go directory when `zigo gen` is
driven by hand, so a file skipped now but written by an earlier run would
linger. `sync_check.compare` would then report it `obsolete` and `zigo check`
would fail — a regeneration that leaves the tree failing its own check is worse
than the empty file. The commit loop therefore has to remove the path it decided
not to write.

### Why `build.zig` has to change too

`build.zig` names all five generated Go files at configure time, long before the
generator has read the semantic document:

- `build.zig:647-650` builds one `gofmt` run per path and copies each captured
  stdout into a `WriteFiles` directory.
- `build.zig:716-720` publishes those same five paths into the user's Go
  directory with `addCopyFileToSource`.

Both enumerations assume the set is fixed. With the generator skipping a file,
`zig build go` fails before it starts:

    error: failed to check cache: '.../scalar_errors_gen.go' file_hash FileNotFound

So the file set has to become something the build learns at run time rather than
declares at configure time. Two things stand in the way, and each has an
established answer in this repository:

- **Formatting.** `formattedGoSources` exists only because `gofmt` runs
  per-file. `gofmt` accepts a directory and recurses, and `doctor.zig:88`
  already shells out with `std.process.run`, so generation can format its own
  output in one call and hand the build an already-formatted directory.
- **Publishing.** `UpdateSourceFiles` copies named files only. Copying a
  directory of unknown contents into the source tree needs a step that walks
  the tree at make time.

## Target structure and invariants

- A prepared `.go` file whose body is only the marker and the `package` clause
  declares nothing and is not written.
- Every path in `emit.all` is owned by this run, so removing one that is being
  skipped touches nothing the user wrote.
- The decision lives in the commit loop, next to the trailing-newline
  normalisation that already inspects rendered Go content. The emitters keep
  their existing early returns; none of them has to learn a new protocol.
- `generate` stays a pure writer with no child processes, so its tests stay
  hermetic. Formatting belongs to the CLI, after generation, over the output
  directory.
- Nothing outside the generator enumerates generated Go paths. `build.zig`
  passes directories; `zigo check` already compares directories and already
  reports a file the generator no longer produces as `obsolete`.
- The publish step prunes: a generated-marker `.go` file in the user's Go
  directory that generation did not produce is deleted, so the tree it leaves
  behind passes `zigo check`.
