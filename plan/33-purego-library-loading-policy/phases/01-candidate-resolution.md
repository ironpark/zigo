---
completed_at: "2026-08-31T06:06:31Z"
depends_on:
- "33-purego-library-loading-policy#0"
perf_phase: false
status: done
---
> DONE-WHEN: Generated code tries the documented order, a multi-candidate failure names every attempted path,
> NEXT: none

# Candidate Path Resolution

## Planned Work

- Emit a resolver that yields the ordered candidates: explicit argument, each configured
  environment variable, each search path, then the platform default name.
- Resolve `${EXECUTABLE_DIR}` through `os.Executable`, join directory entries with
  `DefaultLibraryName`, and skip candidates that cannot be formed.
- Return one `*LibraryError` whose cause joins every failed attempt, and keep a successful load
  atomic, idempotent, and retryable after failure.

## Done When

- Generated code tries the documented order, a multi-candidate failure names every attempted path,
  and a configured example loads from a search path with no explicit argument.
