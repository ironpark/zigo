# SCOPE

- Existing bindings without `.cancel` or `.on_callback_failure` produce identical output.

# CONTEXT

## Current implementation and bottlenecks

- Dispatchers return the sentinel and record the panic on the callback state; nothing tells the running native call to stop.
- The cancel flag pointer is known only to the public wrapper that renders the cancel setup.

## Target structure and invariants

- The callback state (cgo `CallbackState`, purego entry) holds an optional cancel flag pointer set by the wrapper before the native call and cleared after.
- The failure value is decided once by a helper both dispatcher styles use.
