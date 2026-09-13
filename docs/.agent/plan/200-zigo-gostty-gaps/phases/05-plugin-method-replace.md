---
completed_at: "2026-09-13T08:03:10Z"
perf_phase: false
status: done
---
> DONE-WHEN: 억제한 선언의 Go 표면이 플러그인이 쓴 메서드 하나뿐이고 C 심볼은 그대로다.
> NEXT: none

# Plugin method replacement

## Planned Work

- `Plugin`에 선언별 억제 훅을 더하고 contract 버전을 올린다.
- 억제된 선언의 checked 메서드를 비공개 이름으로 내보내고, `MethodInfo`가 그 이름을 준다.
- 억제는 한 선언에 한 플러그인만 주장할 수 있게 하고, 둘이면 진단으로 거절한다.
- `interfaces`·`iterator` 등 메서드 이름을 읽는 내장 플러그인이 새 이름을 따르게 한다.
- 플러그인 contract 테스트에 억제 경로를 더한다.

## Done When

- 억제한 선언의 Go 표면이 플러그인이 쓴 메서드 하나뿐이고 C 심볼은 그대로다.
- 억제하지 않은 기존 골든이 변하지 않는다.
