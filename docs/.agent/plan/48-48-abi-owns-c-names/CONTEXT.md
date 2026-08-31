# SCOPE

- `src/gen/ir/abi.zig` — new `AbiEnum` and `AbiOpaque` records; `AbiScalar.opaque`
  gains its C name; `AbiFn` and `AbiParam` gain their lowered struct record.
- `src/gen/lower.zig` — produce the above.
- `src/gen/emit.zig` — consume the above; delete the minting sites.
- `tests/ir.zig`, `tests/generator_cases/`, in-file tests in `lower.zig`.

# CONTEXT

## Current implementation and bottlenecks

C type names minted inside `emit.zig`:

- `emit.zig:467` — the opaque handle typedef, `<prefix>_<snake>`.
- `emit.zig:473` — the enum typedef, and `emit.zig:479-483` its member
  constants, `<PREFIX>_<ENUM>_<FIELD>` uppercased.
- `emit.zig:542` (`writeCMemberType`) — an enum spelled as a struct member.
- `emit.zig:590` (`writeUnionCParam`) — the tagged union receiver parameter.
- `emit.zig:1535` — the same union name in a cgo pointer cast.

All five duplicate `lower.zig:393 cTypeNameAlloc`.

Separately, `emit.zig` recovers a lowered struct from the semantic name at
lines 792, 810, 817, 871, 880, each a linear search ending in `.?`. The
information is already known at lowering time: it is what produced the
`.struct_in` and `.struct_out` parameter roles. `returnsValueStruct`
(`emit.zig:2505`) is the same reach-through in predicate form. The `.?` sites
are the point — an emitter that cannot fail to find its own record is better
than one that asserts it.

Note that `writeCType` renders `.opaque` as `void`, so opaque parameters cross
as `void *` and do not need the typedef; only the union receiver spells it.

## Target structure and invariants

`abi.Program` gains `enums` and `handles`, each carrying the C name lowering
minted. `AbiScalar.opaque` becomes `{ name, c_name }`, matching `value_struct`,
which already has exactly that shape.

Invariants:

- A C type name appears in the IR exactly once, minted by `lower.zig`.
- The emitter reads C names; it never composes one from `program.prefix`.
- Lookups keyed by a semantic name remain only where one type genuinely refers
  to another by name (`structRecord` for a *nested* struct member, at
  `emit.zig:665`, `686`, `711`), not for a function's own types.
