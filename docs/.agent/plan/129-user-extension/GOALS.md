# GOALS

## Problem and the end result from the user's point of view

Users extend a generated package by adding their own files to it, and by mapping a Zig value struct to a Go type of their choosing. Today generated unexported helpers use plain names (`newContext`, `errorForCode`, `boolToUint8`) that collide with natural user helper names, and every `extern struct` is mirrored as a generated Go struct with no way to substitute one.

After this plan every unexported identifier the public package generates starts with `zigo`, so user files never collide, and a `.value` entry can carry `.go = .{ .type, .import, .to_raw, .from_raw }` so the public API spells the user's Go type and calls the user's conversion functions.

## Measurable goals

- No unexported generated identifier in any example public package lacks the `zigo` prefix (checked by grep).
- A generator case pins an adapted struct; an example uses one and its Go tests round-trip through the user type.
- `zig build test` and every example's Go tests pass on both backends.

## Supported scope and non-goals

Adapters apply to registered `extern struct` value types (not packed structs, enums, unions). Colocated raw packages keep their internal names; the reservation covers the public package. No template overrides.

## Reference source / commit / license

Own code.

## Completion criteria for the whole plan

Both phases done, docs (`generated-code.md` extension section, `bindings-types.md` adapter section, diagnostics), CHANGELOG.
