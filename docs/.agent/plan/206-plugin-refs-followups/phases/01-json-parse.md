---
depends_on:
- "206-plugin-refs-followups#0"
perf_phase: false
status: in-progress
---
> DONE-WHEN: Generated `UnmarshalJSON` for a `.text` enum contains `Parse<Type>(` and, with enumkit, `IsKnown()`, and no `Values()` loop.
> NEXT: none

# json decodes through Parse<Type>

## Planned Work

- In `plugins/json` `renderEnum`, when the enum declaration has `.text` (read `TypeDecl.text` or the equivalent the emitter uses to decide `Parse<Type>`), render `UnmarshalJSON` as: unmarshal the string, `parsed, err := Parse<Type>(text)`; on error return it wrapped in the existing `fmt.Errorf` shape; then, if `enum_known` is provided with `is_known`, reject `!parsed.IsKnown()` with the same error; assign. Without `.text`, keep phase-205 behaviour exactly.
- Golden `plugin_json_enumkit` gains a `.text = true` enum with both plugins; a json-only `.text` enum shows `Parse<Type>` without the gate. Plugin unit tests for the three decode shapes.
- Example 10: if `Mode` lacks `.text`, leave the example as is and rely on the golden; if it has `.text`, regenerate and keep the existing unknown-tag test passing.
- `plugins/json/README.md` documents the decode order; CHANGELOG entry.

## Done When

- Generated `UnmarshalJSON` for a `.text` enum contains `Parse<Type>(` and, with enumkit, `IsKnown()`, and no `Values()` loop.
- Goldens for non-`.text` enums byte-identical; root tests, plugin tests and examples pass.
