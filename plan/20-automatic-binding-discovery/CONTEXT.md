# SCOPE

Changes may touch the public declaration DSL, reflection walker, AST enrichment, build graph inputs, semantic diagnostics/tests, telemetry-hub fixture, and user documentation. Generator IR and output formats remain stable unless newly discovered declarations require expected fixture regeneration.

# CONTEXT

## Current implementation and bottlenecks

`zigo.define` currently preserves an anonymous declaration unchanged. The reflection walker requires `.functions`, and the large telemetry fixture manually lists 51 functions. AST enrichment matches only bare function names and guesses nearby source files, which is ambiguous for methods such as multiple `create` declarations.

## Target structure and invariants

Compiler reflection is authoritative for declaration existence, visibility, function types, receiver types, and conditional compilation. AST parsing supplies only syntax information such as parameter names, docs, and locations. Discovery is explicit opt-in; legacy declarations remain valid; explicit metadata wins over AST and inferred defaults; stable owner-qualified paths identify every function.
