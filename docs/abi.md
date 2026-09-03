# Materialized result buffer ABI

`repr = .materialized` results cross the native boundary as one caller-owned
byte buffer. The format is little-endian and all offsets are unsigned 64-bit
offsets relative to the beginning of that buffer. Pointer values are never
copied into the wire representation.

The version 1 header is 40 bytes:

| Offset | Width | Meaning |
| --- | --- | --- |
| 0 | 8 | magic `ZIGO` and layout version 1 (`0x0001_4f47495a`) |
| 8 | 8 | lowering-assigned root layout id |
| 16 | 8 | root value count |
| 24 | 8 | root record offset, or root-offset-table offset for a slice |
| 32 | 8 | complete buffer length |

Each materialized struct has a lowering-owned `MaterializedLayout`. Its fields
remain in declaration order and occupy fixed 16-byte slots. Scalars use the
first eight bytes. Strings and slices store an offset and length. Embedded
nodes and pointers store a node-record offset (zero is a null optional
pointer); slices of nodes store an offset to a table of node offsets and a
count. Scalar slice elements occupy eight bytes each, and string descriptor
tables use one 16-byte offset/length pair per string.

The layout version and complete field descriptions are part of semantic ABI
comparison. Changing the version, field order, field kind, nested reference,
pointer shape, or nullability is breaking. The generated Zig walker allocates
the buffer with the binding's registered allocator. A result must use
`.returns = .caller` and name a `.release` function accepting `[]u8`; generated
Go copies/decodes the buffer and invokes that release exactly once.
