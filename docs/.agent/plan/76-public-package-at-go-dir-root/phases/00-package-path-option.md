---
perf_phase: false
status: planned
---
> DONE-WHEN: 세 경우의 generator 테스트 통과, 전 예제 `go-check` 변화 없음, 커밋.
> NEXT: none

# 패키지 경로 옵션과 생성 경로

## Planned Work

- `go_package_path` 옵션 추가·검증, 출력 디렉터리·colocation·cgo 상대 경로를 경로 기준으로 계산.
- `--go-package-path` CLI와 emit/report의 import path 계산. generator 단위 테스트(루트, 하위 경로, colocate 세 경우).
- 기본값에서 기존 예제 생성물이 바이트 동일한지 `go-check`로 확인.

## Done When

- 세 경우의 generator 테스트 통과, 전 예제 `go-check` 변화 없음, 커밋.
