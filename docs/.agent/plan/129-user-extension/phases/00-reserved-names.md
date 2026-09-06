---
perf_phase: false
status: in-progress
---
> DONE-WHEN: grep finds no unprefixed unexported generated identifier in example public packages; all tests pass.
> NEXT: none

# Reserved zigo names

## Planned Work

- Rename `errorForCode`, `boolToUint8`, `deleteCallbackHandle`, `activeCallbackHandles`/`Count`, `callbackDispatcherCount`, `new<T>`, `newBorrowed<T>`, `cleanup<T>`, `<t>CleanupState`, `new<Cb>Handle`, `newZigo<Stream>Handle` to `zigo*`.
- Update unit tests, goldens, examples and their hand-written tests.
- Document the reservation and the extension-file pattern in `generated-code.md`; CHANGELOG.

## Done When

- grep finds no unprefixed unexported generated identifier in example public packages; all tests pass.
