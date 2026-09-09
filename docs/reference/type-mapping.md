# 타입 대응 참조

이 문서는 Zig 타입이 공개 Go API에서 어떻게 보이는지와 주요 제한을 요약합니다. 구체적인
선언 예시는 [값과 데이터](../authoring/values-and-data.md)를 참고하세요.

## 스칼라

| Zig | Go | 비고 |
|---|---|---|
| `bool` | `bool` | ABI에서는 정수로 변환 |
| `i8`·`u8` | `int8`·`uint8` | |
| `i16`·`u16` | `int16`·`uint16` | |
| `i32`·`u32` | `int32`·`uint32` | |
| `i64`·`u64` | `int64`·`uint64` | |
| `isize`·`usize` | `int`·`uint` | 대상 포인터 width |
| 비표준 폭 정수 | 다음 표준 폭 | 입력 range 검사로 `error`가 추가될 수 있음 |
| `f32`·`f64` | `float32`·`float64` | 다른 float 폭은 미지원 |
| `void` | 결과 없음 | |

정수는 64 bit 이하만 지원합니다. `u21` 또는 `u32`에 `.semantic = .codepoint`를 지정하면
`rune`으로 생성됩니다.

## error와 optional

| Zig | Go 형태 |
|---|---|
| `E!T` | `(T, error)` |
| `?T` 입력 | `*T` 또는 nil 가능한 대응 타입 |
| `?T` 결과 | `(T, bool)` 또는 nil 가능한 대응 타입 |
| `E!?T` | `(T, bool, error)` |

`anyerror`는 안정된 error code를 만들 수 없어 지원하지 않습니다. 명시적 오류 집합을
사용하세요. optional은 전체 함수 매개변수, 결과 또는 error 페이로드 위치에서만
지원됩니다. 중첩 optional과 콜백의 일반 optional 값은 지원하지 않습니다.
nullable 핸들 포인터는 별도 포인터 표현으로 콜백에 전달할 수 있습니다.

## 열거형

등록 열거형은 이름이 있는 Go 정수 타입과 상수가 됩니다. non-exhaustive 열거형은 반드시
`.exhaustive = false`로 등록합니다. `features.text`를 붙이면 parse와 text 인코딩 메서드가
추가됩니다.

## 구조체

| Zig 형태 | 등록 | 주요 조건 |
|---|---|---|
| `extern struct` | `api.val` | 스칼라, 등록 열거형, 적격 중첩된 extern 구조체 필드 |
| integer-backed `packed struct` | `api.val` | bool, 정수, 등록 열거형·packed 필드 |
| 일반 stateful 구조체 | `api.handle` | 포인터로 사용하고 생성자/소멸자 필요 |
| 일반 결과 tree | `api.materialized` | 지원되는 필드 tree와 caller-owned 해제 필요 |

빈 extern 구조체, 포인터를 포함한 값 구조체와 C 배치를 보장하지 않는 일반 구조체는 값으로
전달하지 않습니다.

## 문자열과 포인터

| Zig | semantic | Go |
|---|---|---|
| `[*:0]const u8` | `.c_string` 또는 inferred 문자열 | `string` |
| 바이트 슬라이스 | `.utf8_string` | `string` |
| 바이트 슬라이스 | `.opaque_bytes` 또는 기본 바이트 의미 | `[]byte` |
| `*T`, `*const T` | 등록 핸들 | `*T`/`*TRef` |

Go 문자열과 슬라이스 입력 포인터는 호출 동안만 유효합니다. 네이티브 코드가 보관하려면 Zig에서
복사해야 합니다. 임의 many 포인터, 변경 가능한 C 문자열과 지원되지 않는 sentinel은 노출하지
않습니다.

## 슬라이스

지원 원소:

- bool, 64 bit 이하 정수와 `f32`·`f64`
- 등록 열거형
- 적격 extern 구조체
- 일부 codepoint와 packed value 경로

포인터를 포함한 임의의 원소, 콜백과 optional 원소는 일반 슬라이스 ABI로 전달하지 않습니다.
UTF-8 의미를 지정한 문자열 슬라이스는 지원되는 예외입니다. 그 밖의 중첩 결과는
materialized 표현을 사용하세요.

입력 슬라이스는 호출 중 빌리고 일반 결과는 Go 메모리로 복사합니다. 네이티브 할당을
반환하면 `zigo.result.releasedBy`로 해제 함수를 연결합니다.

## tagged union

- 핸들 projection은 `Tag`, `As*`, `Variant`로 현재 네이티브 값을 읽습니다.
- 스냅샷은 지원 페이로드를 한 Go 값으로 복사합니다.
- 값 전달은 void, 스칼라, 열거형과 적격 packed·extern 구조체 페이로드만 지원합니다.
- 지원하지 않는 variant는 `.omit`으로 제외하거나 명시적 Zig 접근자로 바꿉니다.

## 콜백

콜백 매개변수로 지원되는 대표 형태:

- bool, 정수, float와 등록 열거형
- 등록 packed value
- 등록 핸들 포인터
- `[*:0]const u8`
- `[*]const u8`와 길이 `usize`의 바이트 pair

일반 슬라이스, extern 구조체, optional 값과 값으로 전달하는 핸들은 콜백 ABI로 넘기지
않습니다. 바이트 슬라이스의 지원 경로와 nullable 핸들 포인터는 예외이며
[콜백 예제](../../examples/04-callback/README.md)에서 확인할 수 있습니다.
purego 콜백 결과는 `void`, `bool` 또는 `i32`로 제한됩니다.

## atomic과 스트림

shared atomic 포인터는 `u32`, `i32`, `u64`, `i64` 원소만 지원하고 호출 동안만 빌립니다.
`*const std.atomic.Value(u32)`는 cancel 계약을 통해 `context.Context`가 될 수 있습니다.

`*std.Io.Reader`와 `*std.Io.Writer`는 호출 범위 스트림 매개변수 또는 제한된 핸들 접근자로
지원합니다. retained, optional, 구조체 필드 또는 콜백 페이로드로 사용할 수 없습니다.

## Go 어댑터

등록 extern value와 열거형, 또는 plain 스칼라 매개변수/result는 사용자 Go 타입 어댑터를
가질 수 있습니다. optional, 슬라이스, tagged-union 태그와 다른 패키지 타입에 메서드를 생성해야
하는 위치에는 사용할 수 없습니다.

경계 조건은 [지원 범위](support-matrix.md), 거부된 shape의 해결 방법은
[진단](diagnostics.md)을 확인하세요.
