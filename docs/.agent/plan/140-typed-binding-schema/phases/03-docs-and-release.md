---
depends_on:
- "140-typed-binding-schema#2"
perf_phase: false
status: planned
---
> DONE-WHEN: 문서에 `param_meta`·`.repr`·`@"opaque"`가 남지 않고 0.15.0 태그가 푸시된다.
> NEXT: none

# Docs and release

## Planned Work

- `docs/bindings*.md`, `cheatsheet.md`, `configuration.md`, `getting-started.md`, `diagnostics.md`(ZIGO057 제거, ZIGO027·054 문구), `limitations.md`를 새 문법으로 다시 쓴다. 구 문법→새 문법 대응표를 `docs/migration-0.15.md`에 둔다.
- CHANGELOG `### Breaking` 작성 후 `scripts/release.sh 0.15.0 --push`.

## Done When

- 문서에 `param_meta`·`.repr`·`@"opaque"`가 남지 않고 0.15.0 태그가 푸시된다.
