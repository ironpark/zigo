---
perf_phase: false
status: planned
---
> DONE-WHEN: 워크플로 파일이 `actionlint`(있으면) 또는 YAML 검증을 통과하고 문서가 갱신됐다. 실제 검증은 다음 태그에서.
> NEXT: none

# 태그 릴리즈 자동화와 fetch 고정

## Planned Work

- `.github/workflows/release.yml`: `0.*` 태그 푸시 → `zig build test` → CHANGELOG 절 추출 → `gh release create`(`GITHUB_TOKEN`). 절 추출은 이번 릴리즈에 쓴 `awk` 규칙을 스크립트로.
- README·`docs/getting-started.md`의 fetch를 최신 태그로 고정. `docs/development.md`에 릴리즈 절차와 fetch 갱신 단계.
- 워크플로는 실제 태그 없이 `workflow_dispatch`로 dry-run 가능하게.

## Done When

- 워크플로 파일이 `actionlint`(있으면) 또는 YAML 검증을 통과하고 문서가 갱신됐다. 실제 검증은 다음 태그에서.
