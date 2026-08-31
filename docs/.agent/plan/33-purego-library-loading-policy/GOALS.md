# GOALS

## Problem and the end result from the user's point of view

The purego backend exposes exactly one loading policy. Every application must call
`LoadLibrary(path)` before any binding call, and the only fallbacks are the fixed
`ZIGO_LIBRARY_PATH` environment variable and the bare platform filename resolved through the
loader search path. A library author who ships a known layout — the artifact next to the
executable, or in a fixed installation directory — cannot express that, cannot make loading
happen automatically, and cannot keep the loader out of the package's public API. Two zigo
purego packages in one process also share the single environment variable.

The end result: `addGoBindings` takes a `library_loading` option that declares where to look, in
what order, whether to load on first use, and whether `LoadLibrary`/`LibraryLoaded` are exported.
The default reproduces today's behavior byte for byte.

## Measurable goals

- A binding set can declare ordered candidate locations, including a path relative to the running
  executable, and the generated loader tries them in that order with one aggregate typed error.
- A binding set can opt into loading on first binding call, so an application that ships a known
  layout calls no loader function at all.
- A binding set can keep the loader unexported, so the generated public package exposes only the
  bound API.
- Each environment variable consulted is configurable, and the default includes a package-specific
  name so two zigo packages in one process do not collide.
- The default option value produces byte-identical output to today's generated files.
- Unsupported combinations fail while constructing the build graph with an actionable message.

## Supported scope and non-goals

- Only the purego backend has a loading policy. Passing `library_loading` with `.backend = .cgo`
  is a build-graph error.
- The public bound API stays backend neutral. This option may only add, remove, or rename the
  loader entry points, never the bound functions, handles, or errors.
- Candidate paths are user-authored strings baked into generated Go. Never bake a machine-specific
  path such as the Zig cache or the build prefix into committed output.
- Do not add library unloading, version negotiation, checksum verification, or a plugin registry.
- Do not change cgo generation, the shared-library artifact contract, or the callback ABI.

## Reference source / commit / license

- Builds on plan `31-shared-library-purego`, which defined the artifact contract, the atomic
  loader, and `DefaultLibraryName`.
- purego `v0.10.2` API in use is unchanged: `Dlopen`, `Dlsym`, `RegisterFunc`, `NewCallback`.

## Completion criteria for the whole plan

- Default, search-path, automatic, and unexported-loader configurations all generate, pass
  `go-check`, and pass `CGO_ENABLED=0` tests on macOS and Linux.
- A failed automatic load reports every candidate it tried.
- `go-report` states the effective loading policy, and the wiki documents the option, the
  candidate order, and the deployment and security consequences.
