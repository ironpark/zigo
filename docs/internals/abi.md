# 생성 ABI

이 문서는 zigo가 Zig와 Go 사이에 생성하는 C ABI, 상태 코드와 semantic metadata의 핵심
계약을 설명합니다. application은 raw package를 직접 사용하지 말고 public Go package를
사용하세요.

## lowering이 ABI를 소유합니다

reflection 결과는 semantic document가 되고 generator의 lowering 단계가 `abi.Program`을
만듭니다. header, Zig shim, cgo, purego와 public wrapper는 같은 program을 읽습니다.
emitter가 각자 type이나 ownership을 다시 판단하지 않는 것이 핵심 invariant입니다.

## 함수 결과와 상태 코드

오류를 전달할 수 있는 함수는 status와 payload를 분리합니다.

| status | 의미 |
|---:|---|
| `0` | 성공 |
| 양수 | `errors.lock.json`에 고정된 Zig error tag |
| runtime 예약 음수 | range, handle, callback 같은 boundary 오류 |
| `-256` 이하 | slot에 저장된 Zig panic sequence |

`errors.lock.json`은 append-only입니다. 기존 error name의 code를 바꾸거나 삭제한 code를 다른
이름에 재사용하지 않습니다.

Zig panic message는 sequence가 있는 고정 slot에 저장되고 status가 해당 sequence를
가리킵니다. Go wrapper는 이를 `*NativePanicError`로 만듭니다. slot이 재사용되면 message가
비어 있을 수 있지만 status와 operation identity는 유지됩니다.

## scalar와 optional

- bool은 C-compatible integer로 변환합니다.
- integer와 float는 lowering에서 정한 고정 width C type을 사용합니다.
- non-standard integer는 다음 표준 width로 승격하고 public Go wrapper가 input range를 검사합니다.
- optional parameter/result는 presence와 payload를 별도 ABI slot으로 표현합니다.
- optional pointer의 null과 optional slice의 absent는 빈 값과 구분합니다.

정확한 public Go spelling은 [타입 대응](../reference/type-mapping.md)을 참고하세요.

## value struct와 tagged union

extern value struct는 layout guard와 field별 scalar 변환을 가집니다. packed value는 backing
integer representation으로 전달됩니다.

ABI-safe tagged union value는 tag와 declaration order의 non-void payload slot로 평탄화됩니다.
variant 추가나 순서 변경은 C signature를 바꾸므로 ABI breaking입니다. handle projection은
별도 accessor symbol을 사용하고 snapshot은 독립 layout을 가집니다.

## buffer

slice는 pointer와 length로 낮춥니다. output/inout buffer는 capacity와 실제 written count를
분리할 수 있습니다. native가 오류를 반환해도 이미 쓴 Go buffer 내용은 되돌리지 않습니다.

caller-owned native buffer는 public wrapper가 Go memory로 복사한 뒤 등록된 release symbol을
정확히 한 번 호출합니다. materialized result는 [별도 binary 형식](materialized-format.md)을
사용합니다.

## handle

raw ABI는 opaque pointer를 전달하고 public runtime이 상태를 관리합니다.

- constructor는 owned pointer를 public handle에 넘깁니다.
- destructor는 owned handle에서 한 번만 호출됩니다.
- borrowed result는 owner lifecycle에 연결되고 native destructor를 갖지 않습니다.
- dependent child는 parent가 살아 있는 동안만 유효합니다.
- panic에 참여한 handle은 poison되어 unsafe destructor를 실행하지 않을 수 있습니다.

## callback

callback은 C calling convention entry point와 `usize` token으로 연결됩니다. cgo와 purego는
서로 다른 dispatcher를 사용하지만 같은 semantic callback identity와 public Go type을
공유합니다.

purego callback entry symbol에는 contract version suffix가 포함될 수 있습니다. Go code와
native shared library가 다른 generation에서 왔다면 load 시 missing symbol로 실패합니다.

`.go_error` callback은 `i32` native result에 failure value를 돌려주고 상세 Go error는 registry에
보관했다가 public boundary에서 반환합니다. callback panic도 trampoline이 recover한 뒤 boundary
밖에서 다시 panic합니다.

## stream과 cancel

Go I/O stream은 function pointer와 call-scoped context로 Zig `std.Io` adapter를 구성합니다.
buffer는 호출 동안만 유효합니다. cancel은 pinned atomic `u32` flag를 전달하며 Zig code가
직접 읽습니다.

이 pointer를 native code가 호출 뒤까지 보관하면 ABI contract 위반입니다.

## C symbol

기본 symbol은 binding `prefix`, owner/namespace와 Go name에서 결정됩니다. 중첩 path는 segment별
snake case로 정규화합니다. explicit `.symbol`은 그대로 사용합니다.

header typedef, function, enum macro와 runtime symbol은 하나의 C identifier namespace에서 충돌을
검사합니다. 충돌은 `ZIGO036`으로 거부됩니다.

## semantic metadata

`semantic.json`은 다음 계약을 기록합니다.

- source declaration path와 보강된 location
- public package와 이름
- parameter/result type과 semantic
- ownership, constructor/destructor와 parent 관계
- callback, stream, cancel과 plugin extension
- lowered C symbol identity

source location은 진단용이며 ABI 비교 대상이 아닙니다. type, symbol, ownership과 materialized
layout은 ABI 비교 대상입니다.

생성기는 모든 output을 memory에서 준비하고 validation/render가 성공한 뒤 source tree에
반영합니다. 최종 filesystem write 도중의 전원 장애까지 transaction으로 복구하지는 않습니다.

구현 정본은 [`abi.Program`](../../src/gen/ir/abi.zig),
[lowering](../../src/gen/lower.zig)과 [validation](../../src/gen/validate/validate.zig)입니다.
