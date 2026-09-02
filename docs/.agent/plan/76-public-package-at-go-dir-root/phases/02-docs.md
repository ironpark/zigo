---
depends_on:
- "76-public-package-at-go-dir-root#1"
perf_phase: false
status: planned
---
> DONE-WHEN: 문서에 "하위 디렉터리 고정" 안내가 남아 있지 않음, `zig build test` 녹색, 커밋.
> NEXT: none

# 문서와 CHANGELOG

## Planned Work

- `docs/configuration.md` 표에 `go_package_path` 추가, 루트 발행·colocate 예시, import path 규칙 갱신. `docs/generated-code.md` 트리 갱신. `docs/limitations.md`의 관련 제약 제거.
- CHANGELOG Unreleased Added.

## Done When

- 문서에 "하위 디렉터리 고정" 안내가 남아 있지 않음, `zig build test` 녹색, 커밋.
