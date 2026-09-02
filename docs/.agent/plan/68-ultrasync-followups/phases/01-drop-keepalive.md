---
perf_phase: true
status: planned
---
> DONE-WHEN: 단정 통과, 예제 전부 통과.
> NEXT: none

# handle 획득 경로의 `KeepAlive` 제거

## Planned Work

- `renderKeepAliveDefers`에서 receiver·`.opaque_ptr` 파라미터의 `KeepAlive` 제거(문자열·슬라이스 데이터 `KeepAlive`는 유지). union accessor 세 템플릿에서 `defer runtime.KeepAlive(receiver)` 제거.
- 남는 `KeepAlive`의 이유를 코드 주석에 적고, 테스트 `:5411`의 기대 수를 0(또는 남는 종류만)으로 갱신. 공개 생성물 전체에서 `defer runtime.KeepAlive(<handle>)` 부재 단정.
- 골든·예제 재생성. `generated-code.md`의 handle 수명 설명 갱신.

## Done When

- 단정 통과, 예제 전부 통과.
