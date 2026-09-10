---
completed_at: "2026-09-10T03:51:54Z"
depends_on:
- "187-plugin-contract-targets#1"
perf_phase: false
status: done
---
> DONE-WHEN: `src/plugin.zig` declares no public `Go`-named type, field or function outside
> NEXT: none

# Rename the neutral contract surface off Go

## Planned Work

- Rename the framing: `GoFile` to `SourceFile`, `GoFileKind` to `FileKind`,
  `GoPackage` to `PackageKind`, `goFilePathAlloc` to `sourceFilePathAlloc` (both
  the module function and the `Context` method), `Plugin.go_files` to
  `Plugin.source_files`.
- Rename the identity: `FunctionInfo.go_name` and `Method.go_name` to
  `public_name`, and `Context.writeDoc`'s `go_name` parameter with them.
- Leave `Options.go_module`, `go_package`, `go_package_path` and
  `go_package_doc` as flat fields, and say on `Options` why. The plan opened by
  proposing an `Options.go` namespace mirroring what plan 185 did to the IR;
  measuring it first showed the analogy does not hold. Plan 185 grouped fields
  in a *shared, language-neutral document* that a second target would have to
  read past. These four sit in an options record that only Go's emitter reads,
  they are already namespaced by their prefix, and grouping them costs roughly
  290 edits, nearly all inside `src/gen/emit/**` -- behind the seam plan 186
  drew. A second target wants its own crate fields beside them, which a
  namespace does not buy. This is the same judgment plan 186 made when it
  declined to route emit's 59 `pascalAlloc` calls through the interface.
- Leave the six Go syntax writers named as they are. Document on each that it
  writes Go and that a plugin calling it belongs to `output_targets = &.{"go"}`.
- Update `docs/plugins/api-reference.md` and `docs/plugins/authoring.md`, and
  add the `CHANGELOG.md` `[Unreleased]` entry for contract 3.0.

## Done When

- `src/plugin.zig` declares no public `Go`-named type, field or function except
  `writeGoType` -- one of the six documented Go syntax writers -- and the four
  `Options` fields naming the Go module system, which carry a comment saying
  they are Go's and why a second target wants siblings rather than a rename.
- The three shipped plugins and the four test plugins compile against 3.0 with
  no compatibility shim.
- `docs/plugins/` names no removed symbol.
- `zig build test --summary all` passes, generator cases regenerate clean, and
  every example passes its full check with no output moved.
