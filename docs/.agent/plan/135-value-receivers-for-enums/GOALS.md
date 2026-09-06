# GOALS

## Problem and the end result from the user's point of view

A method on a Zig enum cannot be bound. `receiver` resolves only to registered
handle types (`reflect/walk.zig` `receiverNameAt` matches `.@"opaque"` entries
and pointers to handle reprs), so a library whose enum carries behaviour has to
grow a free-function wrapper per method on the Zig side, and the binding then
spends a `.covers` entry to keep `go-coverage` honest. The gostty binding pays
this sixteen times for `Key` alone: `root.keyCodepoint`, `root.keyPrintable`,
`root.keyW3C` and friends all exist only because zigo could not say
`Key.codepoint`.

Afterwards a registered enum can be named as a `receiver`, the Zig method binds
directly, and Go sees `func (k Key) Codepoint() rune`. The wrappers and their
`.covers` entries are deleted; the enum's methods are counted as bound because
they are bound.

## Measurable goals

- A registered enum type can be used as `receiver` (explicitly or inferred from
  the first non-injected parameter), for group entries too.
- The generated Go method has a value receiver, no handle check, and no
  lifetime bookkeeping.
- `go-coverage` counts the bound methods without any `.covers` entry.
- The C ABI gains no new wire form: the receiver crosses as the enum's backing
  integer, exactly as an enum parameter does today.
- `examples/13-*` (a new generator case plus its purego twin) covers an enum
  receiver with a scalar return, a string return and a codepoint return.

## Supported scope and non-goals

In scope: registered `.repr = .enumeration` types as receivers, taken by value,
for methods that do not mutate the receiver.

Out of scope for this plan, each rejected with a diagnostic rather than left to
misbehave:

- `.repr = .value` receivers (mirror structs). Field/method name collisions and
  copy-back semantics for `*T` receivers need their own design.
- `*T` receivers of any value kind: Go value receivers would silently drop the
  mutation.
- Enum entries carrying a `.go` adapter: Go forbids methods on a non-local type.
- Ownership metadata on a value receiver: `constructs`, `destroys`,
  `child_of_receiver`, `.returns = .borrowed`, `io` stream parameters,
  `.iterator`, and `interfaces` membership all assume a handle.

## Reference source / commit / license

None; this is zigo's own surface. The motivating consumer is the gostty
binding's `input` package.

## Completion criteria for the whole plan

`zig build test --summary all` passes, the new generator cases and their goldens
compile, existing goldens are unchanged, the diagnostics are documented, and the
cheatsheet plus `bindings-functions.md` describe enum receivers.
