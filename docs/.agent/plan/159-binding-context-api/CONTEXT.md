# SCOPE

Implement Context in author.zig using existing Scope; migrate callback, event-queue, io-streams and materialized.

# CONTEXT

## Current implementation and bottlenecks

Scope and Entry are separate; the research prototype confirms an optional generic context preserves normalized output.

## Target structure and invariants

Context captures original Entry and Scope, preserves source identity and decorations, and returns Entry through define/select.
