---
perf_phase: false
status: in-progress
---
> DONE-WHEN: 예제가 네이티브·크로스에서 통과, 전 예제 녹색, 커밋.
> NEXT: none

# 회귀 재현과 수정

## Planned Work

- 예제에 C++ 정적 라이브러리를 `linkLibrary`로 붙여 현재 `go-lib`가 실패함을 확인.
- 접근을 고르고 `hostReflectionModule`을 수정. 크로스 3종과 네이티브에서 통과 확인.
- CI 크로스 스텝 포함 여부 확인·보강.

## Done When

- 예제가 네이티브·크로스에서 통과, 전 예제 녹색, 커밋.
