---
perf_phase: false
status: in-progress
---
> DONE-WHEN: Findings and exceptions are recorded with evidence; production examples remain unchanged.
> NEXT: none

# Initial Work

## Planned Work

- Audit adoption, validate representative simplifications and write a prioritized review.

## Done When

- Findings and exceptions are recorded with evidence; production examples remain unchanged.

## Review Results and Verification

- Read all 13 bindings, inventoried current API usage, and checked the relevant READMEs and examples guide.
- Recorded five adoption/presentation gaps, a feature-to-example mapping, and explicit reasons not to force optional helpers.
- Temporary public-API candidate rewrites for seven examples passed exact comptime deep equality of the full normalized bindings.
- Recommended migrating 05/08/09/10 while retaining 03 and the full-schema output buffer as explicit teaching baselines.
- Production examples and generated output were not modified. Full runtime checks were not repeated for this review.
- Findings: docs/.agent/reviews/example-feature-adoption.md.
