# Materialized 결과 버퍼 ABI

이 문서는 생성기·디코더를 수정하거나 바이너리 형식을 검토할 때 사용하는 참조입니다.
바인딩 선언은 [값 타입과 결과 트리](bindings-types.md), 일반적인 생성물 관리는
[생성물과 CI 관리](generated-code.md)를 먼저 확인하세요.

## 버퍼 헤더

`.materialized` 결과는 caller-owned byte 버퍼 하나로 전달됩니다.
모든 값은 little-endian이며, offset은 버퍼 시작을 기준으로 한 unsigned 64-bit 값입니다.
native 포인터 자체는 기록하지 않습니다.

버전 2 헤더는 40바이트입니다.

| Offset | 크기 | 의미 |
|---|---|---|
| 0 | 8 | magic `ZIGO`와 layout version 2 (`0x0002_4f47495a`) |
| 8 | 8 | lowering이 배정한 root layout ID |
| 16 | 8 | root 값 개수 |
| 24 | 8 | root record offset; slice 결과라면 root offset table의 offset |
| 32 | 8 | 전체 버퍼 길이 |

## 최상위 optional 반환

`?T`, `!?T`, `?[]T`, `!?[]T`의 `T`가 materialized 값이면 같은 포인터·길이
출력 인자를 사용합니다. null 포인터와 길이 0은 값 없음을 뜻하며 버퍼를 할당하지
않습니다. 존재하는 빈 slice도 헤더가 있는 버퍼로 전달하므로 값 없음과 구분됩니다.
Go raw 반환에는 `bool`이 추가되고, 공개 반환은 `(T, bool)` 또는 `(T, bool, error)`입니다.
Zig 오류는 기존 status로 전달하며, 오류·값 없음 경로는 디코딩하거나 해제하지 않습니다.
존재하는 버퍼는 공개 함수가 디코딩 후 정확히 한 번 해제합니다.

## 필드 표현

각 materialized struct의 `MaterializedLayout`은 lowering에서 결정합니다. 필드는 선언 순서를
유지하며 각 필드는 자기 shape의 자연 정렬에 맞춰 record 안에 놓입니다. record와 배열은
8바이트 경계에서 시작하고 record 크기는 8의 배수로 채웁니다.

| shape | 크기·정렬 | 표현 |
|---|---|---|
| scalar | 1·2·4·8 | bool은 1바이트, 정수·부동소수는 비트 폭을 담는 최소 폭, enum은 tag 폭, packed struct는 backing 정수 폭 |
| string | 16 / 8 | offset과 길이. `?[]const u8`은 offset 0이 null (데이터는 항상 헤더 뒤에 놓이므로 빈 문자열도 0이 아님) |
| optional | child 정렬 + child 크기 | presence 1바이트 뒤 child 정렬 위치에 값 (`?i32`, `?Point`) |
| sequence | 16 / 8 | offset과 원소 수. 원소는 원소 shape의 stride 간격으로 8바이트 정렬된 배열에 놓임 (`[]T`, `[N]T`, `[][]T`) |
| node | 8 | 별도 record의 offset. 내장 값·포인터 모두 같은 표현이며 nullable(`?*const T`, `?T`)은 0이 null |
| value_struct | 필드 합 | `extern struct` 필드를 record 안에 인라인 |

layout version과 전체 필드 정보는 semantic ABI 비교에 포함됩니다. 버전, 필드 순서·종류,
중첩 참조, 포인터 형태나 nullability를 바꾸면 breaking 변경입니다. 버전 1 버퍼는 읽지 않습니다.

## 할당과 해제

Zig walker는 바인딩에 등록한 allocator로 버퍼를 만듭니다. 결과 선언에는
`.returns.ownership = .caller`와 `[]u8`를 받는 `.returns.release` 함수가 필요합니다.
Go raw 계층은 native 버퍼의 view를 그대로 넘기고, 공개 래퍼가 디코딩하면서 필요한 값을 모두
복사한 뒤 release를 한 번 호출합니다. 디코딩 결과는 버퍼를 참조하지 않습니다.

직접 반환, error union payload와 `[]T` 반환을 지원합니다. slice 결과도 배치 전체에
헤더 하나와 버퍼 하나를 사용합니다. out `[]T`는 `.direction = .out`,
`.written = .result`로 선언합니다. 이 경우 용량만 shim에 넘기고, shim이 native
값을 임시 저장한 뒤 작성된 범위를 같은 결과 버퍼 형식으로 직렬화합니다.

## 지원 필드와 검증

scalar, bool, 등록 enum, `extern struct`·packed 값, string과 `[]byte`
(`.fields = &.{.{ .name = "name", .semantic = .opaque_bytes }}`), optional scalar·string·struct·node,
내장 materialized struct, 필수·optional materialized 포인터, 그리고 scalar·string·struct·
materialized struct의 slice와 배열(중첩 가능)을 지원합니다. **트리 내부 필드**의 optional slice(`?[]T`)와 optional
원소(`[]?T`)는 presence를 실을 자리가 없어 거부됩니다.
순환 참조, opaque 포인터, callback과 union은 lowering 전에 `ZIGO048`로 거부하며
진단에 전체 필드 경로를 표시합니다.

구현은 [ABI IR](../src/gen/ir/abi.zig),
[materialized emitter](../src/gen/emit/materialized.zig)와
[검증 규칙](../src/gen/validate/materialized.zig)을 함께 확인하세요.
