---
completed_at: "2026-09-02T06:50:24Z"
depends_on:
- "68-ultrasync-followups#3"
entry_condition: phase 3 벤치마크에서 LockOSThread 쌍이 가벼운 error union 호출 총비용의 10% 이상
perf_phase: true
status: done
---
> DONE-WHEN: 진입 조건이 성립하지 않아 진행하지 않는다. 그 판단이 `docs/limitations.md`에 수치와 함께 남아 있다.
> NEXT: none

# 패닉 메시지 전달을 스레드 고정 없는 ABI로

## Planned Work

**진행하지 않음.** phase 3 벤치마크(`examples/07-event-queue/.../lock_os_thread_bench_test.go`,
Apple M1 Ultra, macOS 15, Go 1.27, `-benchmem -count=5`)에서 `LockOSThread` 쌍의 비용은
cgo 289.2 → 284.4 ns/op(+4.8 ns, 1.7%), purego 516.0 → 505.6 ns/op(+10.4 ns, 2.0%)였다.
쌍 자체는 4.2 ns/op이고 어느 경로에도 추가 할당이 없다. 진입 조건인 10%에 크게 못 미치므로
패닉 메시지 전달 ABI는 그대로 둔다. 후보 (a)/(b)는 모두 breaking이고
`{prefix}_last_error_message` 제거를 요구하는데, 2%를 위해 치를 값이 아니다. 결과와 판단은
`docs/limitations.md`의 런타임 주의사항 절에 기록했다.

원래 계획(조건이 성립했다면 했을 일):

- CONTEXT의 후보 (a)/(b)를 벤치마크로 비교해 하나를 택한다. (b)는 cgo·purego 포인터 인자 escape로 인한 할당을 반드시 측정.
- 택한 설계로 shim·raw·purego·`errorForCode` 갱신, `LockOSThread`와 `{prefix}_last_error_message` 제거. `abi_diff`가 이 변경을 breaking으로 보고하는지 확인(심볼 제거로 자연히 그렇다).
- 골든·예제 재생성, `generated-code.md`의 패닉 경로 설명 갱신.

## Done When

- 진입 조건이 성립하지 않아 진행하지 않는다. 그 판단이 `docs/limitations.md`에 수치와 함께 남아 있다.

원래 조건:

- 공개 생성물에 `LockOSThread` 부재, 패닉 메시지 Go 테스트(핸들 poison 포함) 통과, 벤치마크 개선 수치 기록.
