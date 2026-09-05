# 문자열, 슬라이스와 optional

입력 문자열, 반환 버퍼의 해제, 재사용할 출력 버퍼와 값의 부재를 선언합니다. 선언의 기본 형태는 [`bindings.zig` 선언](bindings.md)을 참고하세요.

반환 slice는 Go 소유 사본입니다. 새 native 버퍼를 반환한다면
[해제 함수](#호출자-소유-slice-반환)를 지정하고, Go 버퍼를 재사용하려면
[out 파라미터](#큰-결과는-out-파라미터로)를 사용하세요.

## Sentinel C 문자열

Zig API가 NUL 종료 포인터를 쓴다면 `[*:0]const u8`를 그대로 노출할 수 있습니다. 이 타입은
별도 `.semantic` 메타데이터 없이 `string`으로 반영됩니다.

```zig
pub fn echoCString(text: [*:0]const u8) [*:0]const u8 {
    return text;
}
```

cgo raw는 호출 중 `C.CString`을 만들고 호출이 끝나면 `free`하며, purego raw는 NUL을 붙인
Go byte buffer를 호출 동안만 native에 전달합니다. 반환 문자열도 호출 시점에 Go `string`으로
복사합니다. 따라서 Go 포인터가 native 메모리로 넘어가지 않습니다. mutable `[*:0]u8`,
0이 아닌 sentinel, 기타 many-pointer는 지원하지 않습니다.

## 문자열 slice 매개변수

여러 문자열을 입력으로 넘길 때는 `[]const []const u8`에 `.utf8_string`을 지정하거나,
element를 `[:0]const u8` 또는 `[*:0]const u8`로 선언할 수 있습니다. 세 형태 모두 public
Go에서는 `[]string`이 됩니다. 일반 unsentinel 형태는 sidecar에서 의미를 지정해야 합니다.

```zig
pub fn extractPaths(paths: []const []const u8) usize { /* ... */ }

// bindings.zig
.{
    .path = "Context.extractPaths",
    .params = .{"paths"},
    .param_meta = .{ .paths = .{ .semantic = .utf8_string } },
},
```

native ABI는 `paths_data`, `paths_data_len`, `paths_lens`, `paths_count` 네 scalar 인자로
내려갑니다. 각 문자열의 바이트 뒤에 NUL을 하나 붙이고 `paths_lens`에는 NUL을 제외한 길이를
기록합니다. cgo와 purego 모두 pointer-free Go 배열 하나씩만 만들어 호출 중 빌려주며
문자열별 malloc은 하지 않습니다. 빈 `[]string`과 빈 문자열 원소도 지원합니다. `[]string`
반환은 지원하지 않습니다.

## 슬라이스 반환 소유권

슬라이스를 반환하는 함수는 호출 시점에 native 메모리에서 Go가 소유한 새 사본을 만듭니다.
따라서 반환된 `[]T`는 다음 native 호출이나 원본 객체의 `Close`와 독립적이며, 호출자는
반환된 사본만 수정할 수 있습니다. tagged-union의 숫자 slice payload도 같은 복사 계약을
따릅니다. 이 복사가 부담이라면 결과를 `.direction = .out` 파라미터로 받는
[`...Into(dst)` 패턴](#큰-결과는-out-파라미터로)을 쓰세요.

실패할 수 있는 slice 반환(`![]T`)도 같은 방식으로 내려갑니다. C 시그니처는 정수 코드를
반환하고 `T** out_result_ptr, size_t* out_result_len`을 그대로 받으며, 공개 Go는
`([]T, error)`가 됩니다. 오류일 때 생성된 코드는 out 파라미터를 읽지 않고 `nil`과 오류를
돌려주므로, native가 아무것도 기록하지 않은 상태를 그대로 안전하게 표현합니다. 원소는
스칼라·enum·`extern struct`를 쓸 수 있습니다. 일반 `![]string` 반환은 지원하지 않으며,
optional slice는 [optional 규칙](#optional)을 함께 따릅니다.

## 호출자 소유 slice 반환

slice 반환은 `.returns = .caller`로 소유권을 넘길 수 있습니다. 이때는 감쌀 handle 대신
버퍼를 되돌려줄 함수가 필요하므로 `.release`로 그 함수의 경로를 함께 지정합니다. release
함수는 반환된 slice와 같은 원소 타입의 slice 하나만 받고 아무것도 반환하지 않아야 합니다.

```zig
pub fn extractSamples(self: *EventQueue) []f32 { /* 새 버퍼를 할당해 반환 */ }
pub fn freeSamples(_: *EventQueue, samples: []f32) void { /* 버퍼 해제 */ }

// bindings.zig
.{
    .path = "EventQueue.extractSamples",
    .returns = .caller,
    .release = "EventQueue.freeSamples",
},
.{ .path = "EventQueue.freeSamples", .params = .{"samples"} },
```

생성된 raw 계층은 native가 채운 `ptr, len`을 먼저 Go slice로 복사한 뒤 곧바로 release
심볼을 같은 `ptr, len`으로 호출합니다. 따라서 반환된 slice는 항상 Go 메모리이고, 호출자가
따로 해제할 것이 없습니다. release 함수는 공개 Go API에 나타나지 않습니다. 이미 복사된
Go slice를 다시 넘기는 실수를 막기 위해서입니다.

`![]T` 반환에도 같은 조합을 쓸 수 있습니다. 이때 복사와 release는 모두 성공했을 때에만
일어납니다. 오류 코드가 돌아오면 생성된 코드는 out 파라미터를 읽지 않고 release도 부르지
않은 채 `nil`과 오류를 돌려주므로, 아무것도 넘겨받지 않은 실패 경로에서 존재하지 않는
버퍼를 해제하는 일이 없습니다.

optional slice도 같은 소유권 규칙을 따릅니다. `?[]T`는 `([]T, bool)`, `!?[]T`는
`([]T, bool, error)`가 되며, sentinel c_string variant는 각각 `(string, bool)`과
`(string, bool, error)`입니다. 부재는 `nil, false`(문자열은 `"", false`), error union의
실패는 zero value, `false`, error로 돌아옵니다. 생성 코드는 성공하면서 존재하는 값만 복사하고
release하므로 부재와 오류 경로에서는 release 함수가 호출되지 않습니다.

```zig
pub fn extractSamplesChecked(self: *EventQueue) ProcessError![]f32 { /* 실패 또는 새 버퍼 */ }

// bindings.zig
.{
    .path = "EventQueue.extractSamplesChecked",
    .returns = .caller,
    .release = "EventQueue.freeSamples",
},
```

release 함수가 allocator를 받아도 됩니다. `fn freeSamples(gpa: Allocator, samples: []f32) void`는
주입 파라미터를 빼고 slice 하나만 받는 함수로 판정되며, shim이 호출할 때 바인딩이 정한
allocator를 채웁니다.

`.release`가 없거나, 이름이 가리키는 함수가 없거나, 그 함수의 매개변수가 반환 slice와
맞지 않으면 `ZIGO016`으로 거부됩니다. `![]T`는 payload slice의 원소 타입으로 비교합니다.
slice가 아닌 반환에 `.release`를 붙여도 같은 코드입니다. abi-check는 release 함수가 바뀌면
breaking으로 봅니다.

`?*T`/`?*const T` 매개변수는 nil을 받을 수 있는 handle 인자가 됩니다. Go에서 nil을
넘기면 native 쪽에는 NULL이 전달되고 `*HandleError`는 발생하지 않습니다. 다만 optional은
"인자가 없어도 된다"는 뜻이지 "닫힌 handle을 넘겨도 된다"는 뜻은 아니므로, nil이 아닌 채
이미 닫힌 handle은 여전히 `*HandleError`입니다.

## 얼마나 채워졌는가: `written`

`.direction = .out`인 slice는 기본값 `.written = .all`로, 호출이 끝나면 버퍼 전체가
채워진 것으로 봅니다. `.written = .@"return"`을 붙이면 함수가 반환한 개수만큼만
채워진 것으로 보고, **그 뒤의 원소는 호출 전 값 그대로**입니다 — `io.Reader`와 같은
모양입니다. 오류로 끝난 호출은 0을 보고하므로 버퍼는 전혀 건드려지지 않습니다.

`.@"return"`은 반환 payload가 `usize`(또는 `!usize`)일 때만 쓸 수 있고, `.out`이 아닌
파라미터에 붙이면 `ZIGO017`로 거부됩니다.

`written`은 C 시그니처의 일부입니다. `.all`인 out slice는 `{name}_written`
(`size_t *`) 출력 파라미터를 하나 더 받지만, `.@"return"`은 개수를 함수의 반환값으로
알리므로 그 파라미터가 없습니다. 따라서 `.all`과 `.@"return"` 사이를 오가는 변경은
어느 방향이든 breaking이고, `abi-check`는 이를
`parameter written hint changed (C signature)`로 보고합니다.

## 큰 결과는 out 파라미터로

slice를 반환하면 호출마다 Go 쪽 할당과 복사가 한 번씩 일어납니다. 결과가 크거나 호출이
잦다면 호출자가 버퍼를 재사용하는 `...Into(dst)` 모양이 낫습니다.

```zig
pub fn extractSamplesInto(self: *Queue, dst: []f32) usize {
    const wanted = self.items.len + 1;
    if (dst.len < wanted) return 0;
    // ... dst[0..wanted] 를 채운다
    return wanted;
}

// bindings.zig
.{
    .path = "Queue.extractSamplesInto",
    .params = .{"dst"},
    .param_meta = .{ .dst = .{ .direction = .out, .written = .@"return" } },
},
```

```go
buf := make([]float32, 1024) // 한 번 할당해 계속 재사용
n, err := queue.ExtractSamplesInto(buf)
// buf[:n] 이 이번 호출의 결과, buf[n:] 는 그대로
```

## optional

`?T`는 매개변수, 반환값, error union payload 이 세 자리에서만 쓸 수 있습니다. `T`로는
bool, 정수(승격 대상인 좁은 정수 포함), 부동소수, 등록 enum, `extern struct`, 그리고
선언된 opaque type의 pointer를 지원합니다.

| Zig | C | Go |
| --- | --- | --- |
| 매개변수 `?T` (scalar·bool·enum) | `const T *x` (NULL = 부재) | `*T` (nil = 부재) |
| 매개변수 `?ExternStruct` | `const T *x` (NULL = 부재) | `*T` (nil = 부재) |
| 매개변수 `?*Handle` | `T *x` | `*Handle` |
| 반환 `?T` | `bool` 반환 + `T *out_result` | `(T, bool)` |
| 반환 `E!?T` | `int32_t` 상태 + `bool *out_result_has` + `T *out_result` | `(T, bool, error)` |
| 매개변수 `?[]T` | `const T *x_ptr, size_t x_len` (`x_ptr == NULL` = 부재) | `*[]T` |
| 매개변수 `?[]const u8`(utf8)·`?[:0]const u8` | 같음 / `const char *x` | `*string` |
| 반환 `?[]T` | `T **out_result_ptr, size_t *out_result_len` (NULL = 부재) | `([]T, bool)` |
| 반환 `?[]const u8`(utf8) | 같음 | `(string, bool)` |

```zig
pub fn shiftPoint(origin: ?Point, delta: i16) ?Point { /* ... */ }
```

```go
origin := Point{X: 1, Y: 2}
shifted, ok := ShiftPoint(&origin, 2) // ok == true
_, ok = ShiftPoint(nil, 2)            // ok == false
```

슬라이스·문자열 optional은 presence 플래그를 따로 두지 않습니다. 슬라이스가 이미 포인터를
갖고 있으므로 그 포인터가 NULL인 것이 부재이고, 길이 0인 **존재하는** 슬라이스와 구별됩니다.
Go에서 `[]T`나 `string`이 아니라 `*[]T`·`*string`인 이유도 같습니다 — nil 슬라이스와 빈
슬라이스는 Go에서 이 구별을 표현하지 못합니다. 반환 `?[]T`와 `!?[]T`는 기존 슬라이스 반환의
소유권 규칙(`.release` 포함)을 그대로 따르고 presence만 더합니다. caller-owned `!?[]T`의
공개 결과는 `([]T, bool, error)`입니다.

부재와 "값이 0인 present"는 서로 다릅니다. 값 자체가 아니라 presence 플래그가 그것을
가리므로, `DoubleWidth(&zero)`는 `0, true`를, `DoubleWidth(nil)`은 `_, false`를
돌려줍니다. error union과 결합할 때도 마찬가지로 error·부재·값이 각각 구별됩니다.

scalar optional을 Go에서 `*T`로 적는 것은 의도한 선택입니다. 제네릭 `Optional[T]` 래퍼를
두는 대신 언어가 이미 가진 nil 포인터를 그대로 씁니다.

`abi-check`는 `T`와 `?T` 사이의 변경을 breaking으로 봅니다. C 시그니처가 통째로 달라지기
때문입니다.

`extern struct`의 field, callback signature, slice 원소(`[]?T`), optional의
optional(`??T`), `.out` 슬라이스 매개변수(버퍼는 호출자가 잡습니다), 슬라이스의
슬라이스(`?[][]const u8`), `extern struct` 슬라이스(`?[]Point`)에는 presence를 실을 자리가
없어 `ZIGO019`(구조체가 걸린 경우 `ZIGO013`)로 거부됩니다. reflection이
표현할 수 없는 child는 그보다 앞선 컴파일 오류입니다.
