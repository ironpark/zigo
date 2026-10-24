# GOALS

## Problem and the end result from the user's point of view

zigo builds only with Zig 0.16. Zig 0.17 split the build system into a
configure process and a separate make runner, which removed custom `makeFn`
steps, `LazyPath.getPath`, `Build.pathFromRoot` and `Build.args`. It also
changed `@typeInfo` to a struct-of-arrays layout (`field_names`/`field_types`/
`field_attrs`, `decl_names`, `param_types`/`param_attrs`, `Pointer.attrs`)
and removed the `**` operator. After this plan, `zig build`, `zig build test`
and every example/plugin build work with Zig 0.17.0, and a consumer's
`addGoBindings` call works unchanged.

## Measurable goals

- `zig build test` passes on Zig 0.17.0.
- Every `examples/*` and `plugins/*` build and its tests pass on 0.17.0.
- `minimum_zig_version` is `0.17.0` everywhere, and CI installs 0.17.0.

## Supported scope and non-goals

Supported: Zig 0.17.0 only. Non-goal: keeping 0.16 compatibility.

## Reference source / commit / license

Zig 0.17.0 standard library (`lib/std/Build.zig`, `lib/std/lang.zig`).

## Completion criteria for the whole plan

All phases done, the full test suite green on 0.17.0, and CHANGELOG notes the
toolchain bump.
