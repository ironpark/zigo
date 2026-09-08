---
perf_phase: false
status: in-progress
---
> DONE-WHEN: External plugins can remove and derive functions, reorder parameters safely, select scalar adapters and set exact public names.
> NEXT: none

# Semantic customization

## Planned Work

- Add transformation, adapter selection and public naming contracts and their ordered pre-validation pipeline.
- Preserve native call order when plugins reorder parameters through the public helper.
- Rename registered types and core references together while preserving native type resolution.
- Route reports through the shared preparation pipeline and expose prepared document serialization.
- Validate transformed output, exercise external plugins on both backends, and document lifecycle and ABI responsibilities.

## Done When

- External plugins can remove and derive functions, reorder parameters safely, select scalar adapters and set exact public names.
- Invalid transformed documents fail before output, and complete test/check/format checks pass.
- Generated shims execute against a real Zig target on both backends, with asymmetric arguments proving preserved meaning.
