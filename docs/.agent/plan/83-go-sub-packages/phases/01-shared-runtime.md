---
completed_at: "2026-09-02T19:09:47Z"
perf_phase: false
status: done
---
> DONE-WHEN: 전 예제 Go 테스트·`go vet` 통과(공개 API 불변 확인), 커밋.
> NEXT: none

# 공용 lifecycle 런타임

## Planned Work

- cgo 백엔드에 `internal/lifecycle` 생성, 비공개 헬퍼·오류를 exported로 이동, 공개 패키지는 alias/재선언으로 표면 유지. purego는 `internal/native`와의 역할 분담을 정한다.
- 활성화 조건(항상 vs `.packages` 있을 때만)을 정해 CONTEXT에 기록. 골든 갱신.

## Done When

- 전 예제 Go 테스트·`go vet` 통과(공개 API 불변 확인), 커밋.
