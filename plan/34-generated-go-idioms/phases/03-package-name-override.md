---
depends_on:
- "34-generated-go-idioms#2"
perf_phase: false
status: in-progress
---
> DONE-WHEN: A binding set can generate an underscore-free package name, the default output is unchanged, an
> NEXT: none

# Public Package Name Override

## Planned Work

- Add an option for the public Go package name, defaulting to the current derivation and validated
  as a Go package identifier.
- Thread it through generation, the raw package resolution that derives names from it, and the
  binding report.
- Document the option, the naming rules of this plan, and why the underscore default is kept.

## Done When

- A binding set can generate an underscore-free package name, the default output is unchanged, an
  invalid name fails while building the graph, and the wiki explains both.
