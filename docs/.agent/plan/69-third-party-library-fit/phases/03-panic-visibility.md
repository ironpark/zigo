---
completed_at: "2026-09-02T07:46:45Z"
depends_on:
- "69-third-party-library-fit#2"
perf_phase: false
status: done
---
> DONE-WHEN: checked 함수 전부에서 패닉이 `error`로 도달하고 poison된다는 테스트 통과. 순수 함수 abort 테스트 통과.
> NEXT: none

# checked infallible 함수의 패닉 가시성

## Planned Work

- `lower.zig`/`emit.zig`: checked infallible 함수(handle 또는 승격 정수)의 C ABI를 상태 반환 + `out_result`로. catch는 `-2`. Go checked 경로에 `errorForCode`·`zigoPoisonAfterPanic` 적용(`writeErrorForCode` 재사용).
- 순수 infallible 함수의 catch를 `abort()`로 바꾸고, 패닉 메시지를 stderr에 먼저 쓴다.
- Go 테스트(03-opaque 또는 04-callback): handle 메서드에서 native 패닉 → `ErrNativePanic`, 이후 호출이 poison 오류. 순수 함수의 abort는 프로세스 테스트(`os/exec`로 자식 실행)로 확인.
- `abi_diff` breaking 보고 테스트, 골든·예제 재생성, `limitations.md`에 패닉 규칙, `CHANGELOG.md` Unreleased에 breaking 기록.

## Done When

- checked 함수 전부에서 패닉이 `error`로 도달하고 poison된다는 테스트 통과. 순수 함수 abort 테스트 통과.
