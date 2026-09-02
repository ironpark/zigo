# GOALS

## Problem and the end result from the user's point of view

When the receiver type belongs to an upstream module, downstream projects cannot add methods to it, so they write free functions (`root.screenSelectAll(screen: *Screen)`) and rename each one by hand with `.name`. The end result: a `.functions` entry may declare a group with a receiver type and a prefix to strip, and each listed free function whose first non-injected parameter is `*T` or `*const T` of that type becomes a Go method on `T` with the prefix removed and the first letter re-cased.

```zig
.functions = .{
    .{ .receiver = "Screen", .strip_prefix = "screen", .functions = .{
        "root.screenSelectAll", "root.screenClearSelection", "root.screenHasSelection",
    }},
    .{ .path = "root.searchMatchCount", .receiver = "Search" },
},
```

## Measurable goals

- Per-entry `.receiver = "Type"` turns a free function into a method on a registered type; reflect verifies the first non-injected parameter is a pointer to that type (else a new diagnostic) and sets `receiver_at`/receiver naming exactly as a real method.
- Group entries: `.receiver`, `.strip_prefix`, `.functions` list of paths or nested entries; the stripped name is the default Go name, `.name` still overrides per item; a path whose Zig name lacks the prefix is a diagnostic.
- Methods attached this way participate in `.constructs`/`.destroys`, `child_of_receiver`, packages (they follow the receiver type), and the lifecycle guard exactly like declared methods; `abi-diff` treats a rename as breaking as today.
- Docs and a generator case plus an example test.

## Supported scope and non-goals

In scope: `walk.zig` metadata schema and validation, `naming.zig` prefix stripping, docs `bindings.md` "함수 메타데이터" additions, generator case, example, CHANGELOG.
Non-goals: automatic receiver inference without `.receiver`; stripping prefixes from types or enums.

## Reference source / commit / license

Current main; plan 74 (receiver after injected params) established `receiver_at`; plan 78 covered receiver name clashes.

## Completion criteria for the whole plan

All phases done; full verification loop green; docs and CHANGELOG updated; tree clean.
