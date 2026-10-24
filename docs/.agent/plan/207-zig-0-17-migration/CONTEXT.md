# SCOPE

build.zig, build/*.zig, src/**, tests/**, plugins/**, examples/**,
.github/workflows, README/CONTRIBUTING and the build.zig.zon files.

# CONTEXT

## Current implementation and bottlenecks

`build/steps.zig` has three custom steps (PublishCgoLinkFlags,
PublishGenerated, ResolvePkgConfigLibraries). `build.zig` resolves LazyPaths
and reads the source tree at configure time. `src/reflect/walk.zig` and
other files read `@typeInfo` with the 0.16 field-record layout.

## Target structure and invariants

The custom steps become subcommands of the generator executable, run through
`Step.Run`. Configure-time file reads are declared with
`dependOnFileContents`/`dependOnDirectoryContents`. The generated Go output
and the public build API stay byte-for-byte the same.
