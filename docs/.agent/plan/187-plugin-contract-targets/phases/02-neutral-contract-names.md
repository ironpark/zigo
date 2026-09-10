---
depends_on:
- "187-plugin-contract-targets#1"
perf_phase: false
status: planned
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
- Group the fields that genuinely describe the Go module system --
  `Options.go_module`, `go_package`, `go_package_path` and the raw-package path
  -- under one `go` namespace on `Options`, the way plan 185 grouped the IR's Go
  fields. A Rust target needs a crate name, which is different data rather than
  a different spelling, so a namespace is the honest shape and a rename would
  not be.
- Leave the six Go syntax writers named as they are. Document on each that it
  writes Go and that a plugin calling it belongs to `output_targets = &.{"go"}`.
- Update `docs/plugins/api-reference.md` and `docs/plugins/authoring.md`, and
  add the `CHANGELOG.md` `[Unreleased]` entry for contract 3.0.

## Done When

- `src/plugin.zig` declares no public `Go`-named type, field or function outside
  the `Options.go` namespace and the six documented syntax writers.
- The three shipped plugins and the four test plugins compile against 3.0 with
  no compatibility shim.
- `docs/plugins/` names no removed symbol.
- `zig build test --summary all` passes, generator cases regenerate clean, and
  every example passes its full check with no output moved.
