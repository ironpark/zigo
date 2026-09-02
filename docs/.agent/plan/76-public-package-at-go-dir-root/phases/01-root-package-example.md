---
completed_at: "2026-09-02T15:12:24Z"
depends_on:
- "76-public-package-at-go-dir-root#0"
perf_phase: false
status: done
---
> DONE-WHEN: 예제가 cgo·purego 통과, 골든·semantic.json 커밋.
> NEXT: none

# 루트 발행 예제

## Planned Work

- 예제 하나를 `go_package_path = "."`로 두고 `go.mod`가 루트에 있는 형태로 구성(cgo·purego 모두). Go 테스트는 `import "<go_module>"`을 쓴다.
- stale 정리가 루트의 `go.mod`·손으로 쓴 테스트 파일을 지우지 않음을 확인.

## Done When

- 예제가 cgo·purego 통과, 골든·semantic.json 커밋.
