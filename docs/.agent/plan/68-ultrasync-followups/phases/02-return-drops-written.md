---
perf_phase: false
status: in-progress
---
> DONE-WHEN: `.return` fixture 헤더·shim·raw·purego에 `_written`/`Written` 부재 단정, `.all` fixture는 유지, abi_diff breaking 테스트 통과.
> NEXT: none

# `.return` out 슬라이스에서 `_written` 제거

## Planned Work

- `lower.zig`: `.written = .return`이면 `.slice_written` 파라미터를 붙이지 않는다.
- `emit.zig`: shim의 `written` 대입·오류 경로 0 대입을 `.all`에만. C 선언, raw cgo, purego에서 `.return` 파라미터의 `Written` 변수·인자 제거. 공개 계층은 반환값을 그대로 사용(이미 그렇다).
- `abi_diff`: `writtenEqual` 차이를 `.breaking`으로, 메시지에 C 시그니처가 바뀜을 명시. 테스트 갱신.
- 골든(`value_struct`의 `fillPoints`)·07-event-queue 재생성. `bindings.md` `.written` 행의 ABI 설명 수정, `generated-code.md`.

## Done When

- `.return` fixture 헤더·shim·raw·purego에 `_written`/`Written` 부재 단정, `.all` fixture는 유지, abi_diff breaking 테스트 통과.
