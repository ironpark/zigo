# GOALS

## Problem and the end result from the user's point of view

Plan 186 put every output-language rule behind `targets.Target` and proved it by
leaving a checklist of what a Rust target implements. Three things could not go
behind that seam because the plugin contract sits in front of it, and plan 186
recorded them as this plan's work:

- `src/plugin.zig` names the output language in its types: `GoFile`,
  `GoPackage`, `GoFileKind`, `Plugin.go_files`, `goFilePathAlloc`,
  `Context.goFilePathAlloc`, `Context.writeGoType`, `FunctionInfo.go_name`,
  `Method.go_name`, `Context.writeDoc`'s `go_name` parameter.
- Because of those, the `ZIGO059` output-path rule in `src/gen/generator.zig`
  hardcodes `.go` and `_test.go`, and the interface-name check in
  `src/plugin/interfaces.zig` calls `targets.default` instead of the target the
  run resolved. Both carry a comment saying why.
- The word `target` already means something else inside the contract.
  `plugin.Target` is the *declaration kind* a plugin attaches to -- function,
  handle, value, enumeration, tagged union, callback, materialized, error set --
  and `Plugin.targets` is the list of them an external plugin writes. So the one
  file that most needs to talk about output targets is the one file where the
  word is taken.

Afterwards the contract says what it means. A plugin declares which output
languages it can render for and which declaration kinds it attaches to, in two
differently named fields. The framing -- file kinds, package kinds, paths,
scopes, public names -- is spelled without naming Go. The parts that genuinely
render Go syntax stay Go's and say so, and a target that a plugin does not
support simply does not run it.

## Measurable goals

- `src/plugin.zig` declares no public type, field or function whose name
  contains `Go`, except the ones that describe the Go module system itself,
  which move into one `go` namespace on `Options`.
- The `ZIGO059` file-shape rule and the interface-name check read the resolved
  target rather than `targets.default`; no `targets.default` reference remains
  in `src/plugin/**` or `src/gen/generator.zig`.
- `Plugin` carries `output_targets` (which languages it can render) separately
  from `subjects` (which declaration kinds it attaches to), and a plugin whose
  `output_targets` excludes the resolved target is not run.
- `plugin.contract_version` is `3.0`.
- Generated output is byte-identical: all 74 generator cases regenerate clean
  and no `.go`, `.zig`, `.h` or `semantic.json` file under `examples/` moves.

## Supported scope and non-goals

In scope: `src/plugin.zig`, `src/plugin/**`, the `ZIGO059` rule, the five
built-in plugins under `src/gen/plugins/`, the three shipped plugins under
`plugins/`, the four test plugins under `tests/plugins/`, the authoring surface
in `src/declare.zig`, `src/author.zig` and `src/features.zig` that names the
declaration-kind axis, and `docs/plugins/`.

Non-goals, each with a reason:

- **The Go syntax writers.** `writeGoType`, `writeSignature`, `writeParameters`,
  `writeResultType`, `writeCallArguments`, `writeValueType` render Go source.
  There is no second emitter for them to dispatch to, so making them generic
  would be a name change dressed as an abstraction. They stay, renamed only
  where the name lies, and `output_targets` is what keeps them honest.
- **A Rust target or a Rust emitter.** Step 4, and not this plan.
- **`src/gen/sync_check.zig`.** Plan 186 left it out for the same reason it is
  left out here: `zigo check` is a tooling entry point with no options record to
  carry a target.
- **The Go initialism table** in `naming.pascalAlloc` and `naming.camelAlloc`,
  and **cancellation**. Both deferred by plan 186 to the plan that adds a second
  target, where the change has a reason to exist.
- **`--gofmt` and `zigo doctor`.** User-visible tooling names.

## Reference source / commit / license

Baseline `ba8e117e` on `main`, which is plans 185 and 186 merged. The checklist
this plan works from is `docs/.agent/plan/186-186-target-interface/PLAN.md`,
section *What a Rust Target Implements*. The research document is
`docs/.agent/research/rust-target-feasibility.md`, which calls this step 3.

## Completion criteria for the whole plan

All three phases `done`, `zig build test --summary all` green at the root,
`scripts/update-generator-cases.sh` leaving `tests/generator_cases` clean, and
every example passing `zig build test go-check go-lib abi-check go-coverage`
followed by `go test ./...` with `git status --short examples tests` empty.
