---
depends_on:
- "192-go-functional-options#2"
- "192-go-functional-options#3"
perf_phase: false
status: in-progress
---
> DONE-WHEN: 골든에 옵션 타입, `With*` 생성자와 가변 인자 생성자가 나타난다.
> NEXT: none

# 공개 Go 생성자 방출

## Planned Work

- `src/gen/emit/public.zig:480`의 시그니처 작성에서 옵션 필드를 빼고 끝에
  `opts ...<Type>Option`을 붙인다.
- 옵션 타입, 기본값으로 초기화되는 비공개 설정 구조체, 필드마다의 `With*` 생성자를
  방출한다. 기본값 문자열은 phase 0이 실은 `FlattenedField.default`에서 온다.
- 함수 본문 시작에 설정 구조체 초기화와 `for _, opt := range opts { opt(&cfg) }`를 쓰고,
  `:374`의 optional raw setup과 `:896`의 인자 포워딩이 설정 구조체 필드를 읽게 한다.
- doc comment에 각 옵션의 기본값을 적는다.
- `src/gen/validate/snapshot_tests.zig`에 옵션 생성자 골든을 추가한다.

## Done When

- 골든에 옵션 타입, `With*` 생성자와 가변 인자 생성자가 나타난다.
- 옵션을 주지 않은 호출이 Zig 기본값과 같은 값을 ABI로 보낸다.
- shim, header, raw, purego 골든이 변하지 않는다.
