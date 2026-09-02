---
perf_phase: false
status: in-progress
---
> DONE-WHEN: 정적 링크 입력이 있는 예제가 `go test` 통과, `extra_ldflags` 골든/테스트 추가, 전 예제 녹색, 커밋.
> NEXT: none

# extra_ldflags와 정적 링크 입력 수집

## Planned Work

- `cgo_flags.extra_ldflags` → `--extra-ldflags` → emit에서 기본(또는 override) 뒤에 덧붙임. generator 테스트 추가.
- `build.zig`에서 `.other_step` 정적 라이브러리와 `.static_path`를 절대 경로로 수집해 정적 백엔드 LDFLAGS에 나열하고 install 스텝 의존을 건다. 캐시 경로와 `go-check` 바이트 비교의 충돌 여부를 확인하고 CONTEXT에 결정 기록.
- 예제 하나에 작은 정적 C 라이브러리를 붙여 cgo에서 링크되는지 검증.

## Done When

- 정적 링크 입력이 있는 예제가 `go test` 통과, `extra_ldflags` 골든/테스트 추가, 전 예제 녹색, 커밋.
