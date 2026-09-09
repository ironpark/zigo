# 타입 대응 참조

이 문서는 Zig type이 public Go API에서 어떻게 보이는지와 주요 제한을 요약합니다. 구체적인
선언 예시는 [값과 데이터](../authoring/values-and-data.md)를 참고하세요.

## scalar

| Zig | Go | 비고 |
|---|---|---|
| `bool` | `bool` | ABI에서는 integer로 변환 |
| `i8`·`u8` | `int8`·`uint8` | |
| `i16`·`u16` | `int16`·`uint16` | |
| `i32`·`u32` | `int32`·`uint32` | |
| `i64`·`u64` | `int64`·`uint64` | |
| `isize`·`usize` | `int`·`uint` | target pointer width |
| 비표준 폭 정수 | 다음 표준 폭 | input range 검사로 `error`가 추가될 수 있음 |
| `f32`·`f64` | `float32`·`float64` | 다른 float 폭은 미지원 |
| `void` | 결과 없음 | |

정수는 64 bit 이하만 지원합니다. `u21` 또는 `u32`에 `.semantic = .codepoint`를 지정하면
`rune`으로 생성됩니다.

## error와 optional

| Zig | Go 형태 |
|---|---|
| `E!T` | `(T, error)` |
| `?T` input | `*T` 또는 nil 가능한 대응 타입 |
| `?T` result | `(T, bool)` 또는 nil 가능한 대응 타입 |
| `E!?T` | `(T, bool, error)` |

`anyerror`는 안정된 error code를 만들 수 없어 지원하지 않습니다. 명시적 error set을
사용하세요. optional은 전체 function parameter, result 또는 error payload 위치에서만
지원되는 경우가 많으며 nested optional과 callback optional은 지원하지 않습니다.

## enum

등록 enum은 named Go integer type과 constant가 됩니다. non-exhaustive enum은 반드시
`.exhaustive = false`로 등록합니다. `features.text`를 붙이면 parse와 text encoding method가
추가됩니다.

## struct

| Zig 형태 | 등록 | 주요 조건 |
|---|---|---|
| `extern struct` | `api.val` | scalar, 등록 enum, 적격 nested extern struct field |
| integer-backed `packed struct` | `api.val` | bool, integer, 등록 enum·packed field |
| 일반 stateful struct | `api.handle` | pointer로 사용하고 constructor/destructor 필요 |
| 일반 result tree | `api.materialized` | supported field tree와 caller-owned release 필요 |

빈 extern struct, pointer를 포함한 값 struct와 C layout을 보장하지 않는 일반 struct는 값으로
전달하지 않습니다.

## string과 pointer

| Zig | semantic | Go |
|---|---|---|
| `[*:0]const u8` | `.c_string` 또는 inferred string | `string` |
| byte slice | `.utf8_string` | `string` |
| byte slice | `.opaque_bytes` 또는 기본 byte 의미 | `[]byte` |
| `*T`, `*const T` | 등록 handle | `*T`/`*TRef` |

Go string과 slice input pointer는 호출 동안만 유효합니다. native code가 보관하려면 Zig에서
복사해야 합니다. 임의 many pointer, mutable C string과 지원되지 않는 sentinel은 노출하지
않습니다.

## slice

지원 element:

- bool, 64 bit 이하 integer와 `f32`·`f64`
- 등록 enum
- 적격 extern struct
- 일부 codepoint와 packed value 경로

pointer가 들어 있는 element, callback, optional element와 중첩 slice를 일반 slice ABI로
넘기지 않습니다. 중첩 result는 materialized 표현을 사용하세요.

input slice는 호출 중 빌리고 일반 result는 Go memory로 복사합니다. native allocation을
반환하면 `zigo.result.releasedBy`로 release function을 연결합니다.

## tagged union

- handle projection은 `Tag`, `As*`, `Variant`로 현재 native 값을 읽습니다.
- snapshot은 지원 payload를 한 Go 값으로 복사합니다.
- 값 전달은 void, scalar, enum과 적격 packed·extern struct payload만 지원합니다.
- unsupported variant는 `.omit`으로 제외하거나 명시적 Zig accessor로 바꿉니다.

## callback

callback parameter로 지원되는 대표 형태:

- bool, integer, float와 등록 enum
- 등록 packed value
- 등록 handle pointer
- `[*:0]const u8`
- `[*]const u8`와 길이 `usize`의 byte pair

slice 자체, extern struct, optional과 by-value handle은 callback ABI로 넘기지 않습니다.
purego callback 결과는 `void`, `bool` 또는 `i32`로 제한됩니다.

## atomic과 stream

shared atomic pointer는 `u32`, `i32`, `u64`, `i64` element만 지원하고 호출 동안만 빌립니다.
`*const std.atomic.Value(u32)`는 cancel contract를 통해 `context.Context`가 될 수 있습니다.

`*std.Io.Reader`와 `*std.Io.Writer`는 호출 범위 stream parameter 또는 제한된 handle accessor로
지원합니다. retained, optional, struct field 또는 callback payload로 사용할 수 없습니다.

## Go adapter

등록 extern value와 enum, 또는 plain scalar parameter/result는 사용자 Go type adapter를
가질 수 있습니다. optional, slice, tagged-union tag와 다른 package type에 method를 생성해야
하는 위치에는 사용할 수 없습니다.

경계 조건은 [지원 범위](support-matrix.md), 거부된 shape의 해결 방법은
[진단](diagnostics.md)을 확인하세요.
