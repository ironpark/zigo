# SCOPE

Type-bound generic contexts, lexical @This behavior, explicit Entry lowering, typed options and source identity.

# CONTEXT

## Current implementation and bottlenecks

Scope already returns a generic type, while representation helpers return Entry values. Examples repeat type names across both.

## Target structure and invariants

Retain one Entry schema and normalizer; distinguish source container, receiver type, constructed type and Go name.
