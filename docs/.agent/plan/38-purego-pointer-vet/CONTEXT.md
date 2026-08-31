# SCOPE

This plan changes the purego raw emitter and the committed purego example output. The cgo emitter,
the semantic IR, lowering and the build graph are untouched.

# CONTEXT

## Current implementation and bottlenecks

- The generated `nativeBindings` binds `lastError` as `func() uintptr`, so `LastErrorMessage`
  dereferences `*(*byte)(unsafe.Pointer(p + i))` in a loop. vet flags the conversion, and the loop
  also re-derives the pointer for every byte.
- `writeRawResultConversion` wraps every opaque-pointer result in `unsafe.Pointer(...)`. That is
  required for the cgo backend, where the value has a C pointer type, but in the purego backend the
  bound function already returns `unsafe.Pointer`, so the conversion is an identity.

## Target structure and invariants

- Bind `lastError` as `func() unsafe.Pointer` and walk the message with `unsafe.Add`, then copy it
  with `unsafe.Slice` and a string conversion. No `uintptr` appears in the path.
- A nil pointer keeps returning the empty string.
- Emit the identity conversion only for the backend that needs it.
