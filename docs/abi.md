# Materialized 결과 버퍼 ABI

이 문서는 생성기·디코더를 수정하거나 바이너리 형식을 검토할 때 사용하는 참조입니다.
바인딩 선언은 [값 타입과 결과 트리](bindings-types.md), 일반적인 생성물 관리는
[생성물과 CI 관리](generated-code.md)를 먼저 확인하세요.

## 버퍼 헤더

`.repr = .materialized` 결과는 caller-owned byte 버퍼 하나로 전달됩니다.
모든 값은 little-endian이며, offset은 버퍼 시작을 기준으로 한 unsigned 64-bit 값입니다.
native 포인터 자체는 기록하지 않습니다.

버전 1 헤더는 40바이트입니다.

| Offset | 크기 | 의미 |
|---|---|---|
| 0 | 8 | magic `ZIGO`와 layout version 1 (`0x0001_4f47495a`) |
| 8 | 8 | lowering이 배정한 root layout ID |
| 16 | 8 | root 값 개수 |
| 24 | 8 | root record offset; slice 결과라면 root offset table의 offset |
| 32 | 8 | 전체 버퍼 길이 |

## 필드 표현

각 materialized struct의 `MaterializedLayout`은 lowering에서 결정합니다.
필드는 선언 순서를 유지하며 각 필드가 고정 16바이트 슬롯을 차지합니다.

| 필드 | 슬롯 또는 참조 대상의 표현 |
|---|---|
| scalar | 슬롯의 앞 8바이트 |
| string·slice | offset와 길이 |
| 내장 노드·노드 포인터 | node record offset; optional 포인터의 0은 null |
| 노드 slice | node offset table의 offset와 원소 수 |
| scalar slice의 원소 | 원소당 8바이트 |
| string slice의 원소 | 문자열마다 16바이트 offset·길이 쌍 |

layout version과 전체 필드 정보는 semantic ABI 비교에 포함됩니다. 버전, 필드 순서·종류,
중첩 참조, 포인터 형태나 nullability를 바꾸면 breaking 변경입니다.

## 할당과 해제

Zig walker는 바인딩에 등록한 allocator로 버퍼를 만듭니다. 결과 선언에는
`.returns = .caller`와 `[]u8`를 받는 `.release` 함수가 필요합니다.
Go 코드는 받은 버퍼를 복사·디코딩한 뒤 release를 한 번 호출합니다.

직접 반환, error union payload와 `[]T` 반환을 지원합니다. slice 결과도 배치 전체에
헤더 하나와 버퍼 하나를 사용합니다. out `[]T`는 `.direction = .out`,
`.written = .@"return"`으로 선언합니다. 이 경우 용량만 shim에 넘기고, shim이 native
값을 임시 저장한 뒤 작성된 범위를 같은 결과 버퍼 형식으로 직렬화합니다.

## 지원 필드와 검증

scalar, bool, 등록 enum, string, 내장 materialized struct, 필수·optional materialized
포인터와 scalar·string·materialized struct의 slice를 지원합니다.
순환 참조, opaque 포인터, callback과 union은 lowering 전에 `ZIGO048`로 거부하며
진단에 전체 필드 경로를 표시합니다.

구현은 [ABI IR](../src/gen/ir/abi.zig),
[materialized emitter](../src/gen/emit/materialized.zig)와
[검증 규칙](../src/gen/validate/materialized.zig)을 함께 확인하세요.
