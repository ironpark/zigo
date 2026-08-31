# SCOPE

This plan changes the build option surface, the generator CLI, the purego raw and public
emitters, the binding report, one example, and the user documentation. Semantic IR, lowering, the
C ABI, the cgo backend, and the artifact contract are unchanged.

# CONTEXT

## Current implementation and bottlenecks

- `emit.renderPuregoRaw` writes a fixed `LoadLibrary`: explicit argument, then
  `os.Getenv("ZIGO_LIBRARY_PATH")`, then `DefaultLibraryName`. The public emitter always
  re-exports `LoadLibrary`, `LibraryLoaded` and `DefaultLibraryName` when the raw package is not
  colocated.
- `bindings()` panics when nothing is loaded. There is no first-use hook, so automatic loading has
  no place to happen and an application cannot avoid the explicit call.
- The single hardcoded environment variable is process global. Two generated purego packages in
  one process read the same value and would load the same file.
- `LoadLibrary` returns the error of the one path it tried. With several candidates the caller
  needs to know which ones were attempted and why each failed.
- Build options are plain fields validated by `@panic` in `addGoBindings`; `src/build_options.zig`
  already holds the validation helpers shared with `src/`.

## Target structure and invariants

- Add `Options.library_loading: LibraryLoading` with `search_paths`, `env_vars`, `automatic` and
  `exported_api`. Defaults reproduce current output; `env_vars` defaults to the package-specific
  name followed by `ZIGO_LIBRARY_PATH`.
- One generated resolver builds the ordered candidate list. `LoadLibrary` with a non-empty
  argument still uses exactly that path. Candidate entries that name a directory are joined with
  `DefaultLibraryName`; `${EXECUTABLE_DIR}` resolves through `os.Executable`.
- Loading stays atomic and idempotent. Automatic loading attempts the candidate list at most once,
  and an explicit call may still succeed afterwards.
- A failed multi-candidate load returns one `*LibraryError` whose cause joins every attempt.
- `exported_api = false` requires `automatic = true`, keeps the loader unexported in the raw
  package, and omits the public wrappers.
- Validation lives in `src/build_options.zig` so the build graph and the generator apply one rule
  set.
