---
completed_at: "2026-09-02T14:28:19Z"
perf_phase: false
status: done
---
> DONE-WHEN: 새 골든의 Go가 `go vet` 통과, 전 예제 녹색, 커밋.
> NEXT: none

# optional 반환의 검사 실패 경로

## Planned Work

- `writeCheckedErrorReturn`이 optional payload에 presence `false`를 넣도록 수정. 가능하면 panic 경로와 실패 반환 목록을 공유.
- 골든 케이스 추가(handle 검사·range 검사·optional handle 파라미터 × optional 반환), cgo·purego.
- 예제에 optional 반환 메서드 추가 및 Go 테스트.

## Done When

- 새 골든의 Go가 `go vet` 통과, 전 예제 녹색, 커밋.
