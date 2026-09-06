---
perf_phase: false
planr_base: sha256:b53ed4c8b2772b3770c0fadf64b746ed9bfb3d967874921edbc8a11ccce18183
planr_edit: "value-receivers-for-enums#0"
planr_phase: 0
planr_slug: reflect-enum-receivers
planr_target: docs/.agent/plan/135-value-receivers-for-enums/phases/00-reflect-enum-receivers.md
status: in-progress
---
> DONE-WHEN: `semantic.json` for an enum-receiver fixture shows the method under its
> NEXT: none

# Reflect enum receivers

## Planned Work

- Resolve a function path through a registered enumeration entry, so
  `.path = "Key.codepoint"` reaches the method.
- Make the enum a receiver only when the binding said so: the path was
  addressed through it or `.receiver` names it, and the first parameter Go
  would see is that enum by value. Plain inference is deliberately left alone
  so an existing `root.colorNameDefault(name: ColorName)` does not silently
  become a method. `*Enum` is rejected with the existing receiver issue.
- Accept the enum name on receiver groups, `strip_prefix` included.
- Add the receiver kind to `semantic.SemanticFn` and to `semantic.json`, with
  `receiverIsHandle()` as the accessor the rest of the tree uses.
- Confirm coverage counts the bound method without `.covers`: the enum's
  container is already walked with the entry name as the path prefix, and
  `markWrapped` only reclassifies unbound declarations, so nothing double
  counts.
- Reflection-level tests: enum receiver addressed by path, declared with
  `.receiver`, in a group, `*Enum` rejected, and a function that merely takes
  the enum left as a package-level function.

## Done When

- `semantic.json` for an enum-receiver fixture shows the method under its
  receiver with the value kind, and `go-coverage` reports the method as bound
  with no `.covers`.
- Existing goldens are byte-identical.
