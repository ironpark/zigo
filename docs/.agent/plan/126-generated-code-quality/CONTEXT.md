# SCOPE

- `src/gen/emit/callbacks.zig`, `public_runtime.zig`, `public.zig`: pending
  callback-panic counter and guarded sweep.
- `src/gen/emit/common.zig`, `public_writers.zig`, `public.zig`,
  `handles.zig`, `public_types.zig`, `docs.zig`: per-type receiver name and
  GoDoc first line.
- `src/gen/emit/raw.zig`, `purego.zig`, `public.zig`, `public_writers.zig`:
  string and struct-slice copy paths, layout guards for every mirror.
- `src/gen/emit/shim.zig` (panic.c), `header.zig`, `raw.zig`, `purego.zig`,
  `public_types.zig` (errorForCode), `public.zig`: panic slot table.
- Generator cases, examples, docs (`generated-runtime.md`, `generated-abi.md`,
  `bindings-buffers.md`), CHANGELOG.

# CONTEXT

## Current implementation and bottlenecks

- `renderCallbackRethrows` emits `for slot := range N { zigoRethrowCallbackPanic(...) }`
  after every native call on a type that owns callbacks; `TakeCallbackPanic`
  locks the state and clears it.
- `common.receiverVariableAlloc(receiver, go_names)` picks the shortest prefix
  of the snake-case type name that no parameter of *this* method uses, so it
  varies per method. Type-level methods pass an empty list.
- `docs.writeGoDoc` writes `// Name` then the doc on its own line when the
  first doc sentence is capitalized.
- `writeCgoSliceReturn` uses `C.GoBytes` for bytes and a per-field loop for
  non-castable struct elements; the public layer then applies `string(...)`
  or `zigoTSliceFromRaw`. Raw `TData` mirrors carry a layout guard against
  `C.T` only when castable.
- panic.c keeps the message in `_Thread_local` storage and every fallible
  wrapper returns `-2`; the public function pins the thread so
  `zg_last_error_message` reads the same TLS.

## Target structure and invariants

- Raw layer: `pendingCallbackPanics atomic.Int64`, incremented in `record`
  (first panic only) and decremented in `TakeCallbackPanic`; exported
  `PendingCallbackPanics()`. Public: the whole rethrow block runs under
  `if raw.PendingCallbackPanics() != 0`.
- `common.typeReceiverNameAlloc(program, type_name)`: shortest prefix of the
  snake-case name that no Go parameter name (including flattened fields) of
  any function with that receiver uses. Every receiver-name call site uses it.
- `writeGoDoc`: a capitalized first sentence becomes `// Name: Sentence`.
- Raw returns UTF-8 strings as `string` (`C.GoStringN` / `unsafe.String` copy
  in purego) and takes UTF-8 inputs as `string`, reading the pointer with
  `unsafe.StringData`. Public passes and returns strings without conversion.
- Raw struct-slice returns copy the C run as one `copy` into `[]TData` for
  every record, guarded by `Sizeof`/`Offsetof` assertions emitted for every
  mirror; only the public layer converts.
- panic.c: 64-entry message table, `_Atomic` sequence; a caught panic returns
  `-(256 + (seq & 0x7fffff))` and `zg_panic_message(int32_t code)` returns
  the message if the slot still holds that sequence, else "". `errorForCode`
  maps `code <= -256` to `*NativePanicError`. `zg_last_error_message` stays
  exported for tooling. No public function pins the OS thread for it.
