---
description: "gostty 작성 중 드러난 zigo 갭 5건 개선: HandleField.ext, optional/slice 필드 leaf, alias 리플렉션, .symbol 오버라이드, 파라미터 이름 오독"
plan_status: in-progress
registered_at: "2026-09-07T23:44:04Z"
---
> NEXT: HandleField.ext 추가. ([Phase 0](phases/00-handle-field-ext.md))

# Phases

- [x] [Phase 00: HandleField.ext](phases/00-handle-field-ext.md)
- [x] [Phase 01: Optional and slice field leafs](phases/01-field-leaf-optional-slice.md)
- [x] [Phase 02: Alias enrichment](phases/02-alias-enrichment.md)
- [ ] [Phase 03: Symbol override](phases/03-symbol-override.md)
- [ ] [Phase 04: Fallback name gating](phases/04-fallback-name-gating.md)
- [ ] [Phase 05: Docs and changelog](phases/05-docs-changelog.md)

# Shared Verification

`zig build test`, generator case 스냅샷 비교, 필요 시 examples 빌드.

# Decisions That Constrain Ordering

0 → 1, 나머지 독립, 5 마지막.

# Next Implementation Target

HandleField.ext 추가.
