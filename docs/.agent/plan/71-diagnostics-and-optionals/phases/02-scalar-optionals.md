---
perf_phase: false
status: in-progress
---
> DONE-WHEN: fixture 골든과 예제 테스트가 cgo·purego에서 통과.
> NEXT: none

# 스칼라·enum·extern struct optional

## Planned Work

- `walk.zig`: optional child를 스칼라·bool·enum·승격 정수·extern struct로 확장. `validate.zig`: 위치 규칙(필드·callback·슬라이스 원소는 거부). `lower.zig`: presence + 값. `emit.zig`: shim(`if (has) x else null`), C 선언, raw cgo·purego, public(`*T` 파라미터, `(T, bool)` 반환, error union 조합).
- 골든 `tests/generator_cases/optional`, 예제(02-errors 또는 09-type-relations)에 사용과 Go 테스트. `abi_diff` breaking 테스트.
- 문서.

## Deviation From CONTEXT

CONTEXT는 스칼라 `?T` 파라미터를 C에서 `bool has_x, T x` 두 인자로 내리기로 했으나,
구현은 `extern struct`와 같은 nullable pointer 하나(`const T *x`, NULL = 부재)로 통일했다.
포인터 하나가 이미 presence와 값 두 상태를 모두 담으므로 별도 플래그가 필요 없고,
스칼라와 `extern struct`의 lowering·emit 경로가 한 갈래로 유지된다. Go 표면은 CONTEXT
그대로(`*T` 파라미터, `(T, bool)`/`(T, bool, error)` 반환)이므로 사용자가 보는 API는
달라지지 않는다. 반환과 `E!?T`는 CONTEXT대로 presence `bool` 반환 + `T *out_result`,
상태 코드 + `bool *out_result_has` + `T *out_result`이다.

거부 위치는 새 코드 대신 기존 `ZIGO019`에 optional 전용 메시지와 힌트를 붙였다.
`ZIGO025`는 쓰지 않았다.

## Done When

- fixture 골든과 예제 테스트가 cgo·purego에서 통과.
