---
depends_on:
- "83-go-sub-packages#2"
perf_phase: false
status: in-progress
---
> DONE-WHEN: 예제 통과, 문서 갱신, 전 예제 녹색, 커밋.
> NEXT: none

# 예제, 문서, CHANGELOG

## Planned Work

- 예제를 두 패키지로 나누고 cgo·purego Go 테스트(교차 참조, 오류 sentinel `errors.Is`, godoc).
- `docs/bindings.md`, `docs/configuration.md`, `docs/generated-code.md`, `docs/limitations.md`, CHANGELOG Unreleased Added.

## Done When

- 예제 통과, 문서 갱신, 전 예제 녹색, 커밋.
