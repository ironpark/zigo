---
depends_on:
- "86-callback-void-return-and-retained-handle-leaks#0"
perf_phase: false
status: in-progress
---
> DONE-WHEN: Re-registering a retained callback on a method no longer leaks; Close/cleanup release method-registered handles; example Go tests on cgo and purego prove the count returns to zero; full verification loop green.
> NEXT: none

# Retained callback ownership on methods

## Planned Work

- Extend `typeOwnsCallbacks` to methods (receiver of the type) with retained callback params, so the handle struct, cleanup state, `Close`, and `cleanup<Type>` get the callback storage even without a retaining constructor.
- Replace the `callbackHandles` slice with per-slot storage (slice keyed by a fixed slot index computed at generation time is fine; a map is not required). Constructors fill their slots; methods swap their slot after a successful native call and delete the previous handle; error path deletes the new handle as today.
- Apply the same to the shared-lifecycle runtime used by `.packages`.
- Extend an existing callback example (07 or whichever has retained callbacks) with a method that re-registers a retained callback; Go test registers twice, closes, asserts active handle count returns to the starting value; run 07 with `-race`.
- Update `docs/` callback retention text and CHANGELOG.

## Done When

- Re-registering a retained callback on a method no longer leaks; Close/cleanup release method-registered handles; example Go tests on cgo and purego prove the count returns to zero; full verification loop green.
