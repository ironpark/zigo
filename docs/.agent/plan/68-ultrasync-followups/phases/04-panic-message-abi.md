---
depends_on:
- "68-ultrasync-followups#3"
entry_condition: phase 3 벤치마크에서 LockOSThread 쌍이 가벼운 error union 호출 총비용의 10% 이상
perf_phase: true
status: conditional
---
> DONE-WHEN: 공개 생성물에 `LockOSThread` 부재, 패닉 메시지 Go 테스트(핸들 poison 포함) 통과, 벤치마크 개선 수치 기록.
> NEXT: none

# 패닉 메시지 전달을 스레드 고정 없는 ABI로

## Planned Work

- CONTEXT의 후보 (a)/(b)를 벤치마크로 비교해 하나를 택한다. (b)는 cgo·purego 포인터 인자 escape로 인한 할당을 반드시 측정.
- 택한 설계로 shim·raw·purego·`errorForCode` 갱신, `LockOSThread`와 `{prefix}_last_error_message` 제거. `abi_diff`가 이 변경을 breaking으로 보고하는지 확인(심볼 제거로 자연히 그렇다).
- 골든·예제 재생성, `generated-code.md`의 패닉 경로 설명 갱신.

## Done When

- 공개 생성물에 `LockOSThread` 부재, 패닉 메시지 Go 테스트(핸들 poison 포함) 통과, 벤치마크 개선 수치 기록.
