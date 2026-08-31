# GOALS

## Problem and the end result from the user's point of view

Generated public constructors accept anonymous callback function types, then erase them through `newCallbackHandle(any)`. Generate stable role-specific callback types and typed handle creators so callback misuse is rejected at compile time and APIs are self-documenting.

## Measurable goals

- Emit a public defined Go callback type for every callback role using owner and parameter identity.
- Use that type in generated public function signatures.
- Generate a callback-specific private handle helper with no `any` parameter.
- Preserve raw-package trampolines by storing the callback as its unnamed underlying function type.

## Supported scope and non-goals

Cover all currently supported callback signatures, retained and borrowed callback lifetimes, separate and colocated raw packages, and multiple callbacks in one package. Keep `cgo.Handle`, raw ABI signatures, panic recovery, and generic handle deletion unchanged. Do not redesign callback error propagation or add nil-callback policy in this change.

## Reference source / commit / license

Use Go's defined-type conversion and the existing generated callback fixtures as references. No third-party source is copied.

## Completion criteria for the whole plan

Generator tests, golden fixtures, callback examples, documentation, root checks, and every example suite pass with no generated `newCallbackHandle(value any)` remaining in callback-enabled packages.
