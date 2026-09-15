---
depends_on:
- "205-plugin-refs-and-capabilities#2"
perf_phase: false
status: in-progress
---
> DONE-WHEN: Example 10 `go-verify` (+ purego) and `go test ./...` pass with the capability-driven `UnmarshalJSON`; goldens for json without enumkit unchanged.
> NEXT: none

# json consumes enumkit

## Planned Work

- `enumkit` provides `plugin.capabilities.enum_known` with `Facts = struct { is_known: bool, values: bool }` recorded in `analyze` per enum it renders for.
- `json` `uses` it: when `is_known` is provided for an enum, `UnmarshalJSON` rejects unknown tags by calling the generated `IsKnown()` instead of the generated `switch` (smaller code, one source of truth); otherwise the current `switch` stays. Rust slot unchanged unless enumkit's Rust `is_known` is present, in which case mirror it.
- Example 10 already uses both plugins on `Mode`; regenerate and add a Go test asserting an unknown tag fails to unmarshal.
- Docs: `docs/plugins/authoring.md` section "Consuming another plugin's capability" using json/enumkit; `plugins/json/README.md`; `docs/plugins/README.md` table gains a capabilities column; CHANGELOG entries; "Plugin API 7.0" table complete.

## Done When

- Example 10 `go-verify` (+ purego) and `go test ./...` pass with the capability-driven `UnmarshalJSON`; goldens for json without enumkit unchanged.
