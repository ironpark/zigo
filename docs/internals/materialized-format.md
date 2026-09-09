# Materialized 결과 형식

materialized result는 nested pointer, string과 slice tree를 caller-owned byte buffer 하나로
직렬화합니다. public Go decoder는 모든 값을 Go memory로 복사한 뒤 native buffer를 해제합니다.

## header

현재 layout version은 2이며 header는 40 byte입니다. 모든 integer는 little-endian이고 offset은
buffer 시작 기준 unsigned 64-bit 값입니다.

| offset | 크기 | 의미 |
|---:|---:|---|
| 0 | 8 | magic `ZIGO`와 layout version 2 (`0x0002_4f47495a`) |
| 8 | 8 | root layout ID |
| 16 | 8 | root value count |
| 24 | 8 | root record 또는 root offset table 위치 |
| 32 | 8 | 전체 buffer 길이 |

native pointer 자체는 기록하지 않습니다.

## record

field는 Zig declaration order를 유지하고 각 shape의 natural alignment에 맞춥니다. record와
array는 8-byte boundary에서 시작하고 record 크기도 8의 배수로 padding합니다.

| shape | 표현 |
|---|---|
| scalar | 1·2·4·8 byte 최소 폭; enum은 tag, packed value는 backing integer |
| string | `offset:u64`, `length:u64` |
| optional value | presence byte와 정렬된 child payload |
| sequence | `offset:u64`, `count:u64`; aligned element array |
| node | 별도 record의 `offset:u64`; 0은 nullable node의 null |
| extern value | field를 record 안에 inline |

string data는 header 뒤에 있으므로 optional string의 offset 0은 absent를 의미할 수 있습니다.
빈 string과 absent string은 구분됩니다.

## 최상위 optional

`?T`, `!?T`, `?[]T`, `!?[]T`의 materialized payload는 같은 pointer/length ABI를 사용합니다.
null pointer와 길이 0은 값 없음이며 buffer를 할당하지 않습니다. 존재하는 빈 slice는 header가
있는 buffer이므로 absent와 구분됩니다.

error 또는 absent 경로에서는 decode와 release를 실행하지 않습니다. 존재하는 buffer는 성공·
decode failure 여부에 맞는 public cleanup path에서 한 번 해제합니다.

## allocation과 release

serializer는 binding에 등록한 allocator로 buffer를 만듭니다. 해당 result는 caller-owned이고
`[]u8`를 받는 release function과 연결되어야 합니다.

```zig
api.func("snapshot", .{
    .returns = zigo.result.releasedBy(api.ref("release")),
}),
api.func("release", .{}),
```

public Go result는 native buffer를 참조하지 않습니다.

## 지원 tree

지원:

- scalar, bool, 등록 enum
- extern/packed value
- UTF-8 string과 opaque `[]byte`
- optional scalar, string, struct와 node
- materialized struct와 required/optional pointer
- 지원 element의 slice와 array, nested sequence

미지원:

- cycle
- opaque pointer
- callback과 tagged union field
- tree 내부의 optional slice와 optional element
- 해석할 수 없는 pointer ownership

위반은 전체 field path가 포함된 `ZIGO048`입니다.

layout version, field order·shape, nested reference와 nullability는 ABI 비교 대상입니다. version 1
buffer는 읽지 않습니다.

구현 정본은 [ABI IR](../../src/gen/ir/abi.zig),
[serializer](../../src/gen/emit/materialized_encoder.zig),
[decoder](../../src/gen/emit/materialized_decoder.zig)와
[validation](../../src/gen/validate/materialized.zig)입니다.
