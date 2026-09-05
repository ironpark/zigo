# 소유권 모델 검토

> 과거 검토 기록입니다. 아래의 “현재”는 조사 당시를 가리킵니다. 소유권의 ABI IR 중앙화는
> 이후 구현되었습니다. 현재 구조는 [IR 명세](02-ir-spec.md), 사용자 계약은
> [객체 수명](../../bindings-handles.md)을 참고하세요.

계획 `110-ownership-and-interface-review`의 결과 문서다. 1절은 현재 구현이 native 메모리를
넘기거나 빌리는 모든 경로의 인벤토리이고, 2절 이후는 그 경로를 IR의 일급 개념으로 묶는
설계와 권고다. 코드 변경은 없다. 인용한 심볼은 계획 109 이후 트리 기준이다.

## 1. 현재 소유권 경로 인벤토리

### 1.1 IR이 소유권을 말하는 자리

`semantic.json`에는 소유권이라는 하나의 개념이 없다. 다음 필드가 각자 한 조각씩 맡는다.

| 필드 | 자리 | 뜻 |
|---|---|---|
| `ownership` (`borrowed`, `caller`, `library`) | `SemanticFn` | 반환값을 누가 소유하는가. `library`는 enum 값만 있고 generator 어디에서도 읽지 않는다. |
| `release` | `SemanticFn` | `.returns = .caller` slice 또는 materialized 버퍼를 되돌려줄 함수 이름 |
| `borrowed_return` | `SemanticFn` | `.returns = .borrowed`를 명시했다는 표시. 기본값도 `borrowed`라 별도 비트가 필요하다. |
| `child_of_receiver` | `SemanticFn` | 생성된 handle이 receiver보다 먼저 닫혀야 한다. |
| `boxed` (`create`, `destroy`) | `SemanticFn` | 값 생성자를 shim이 allocator로 boxing하는 짝 |
| `constructors[]` (`type`, `init`, `deinit`) | `Semantic` | handle의 생성자와 소멸자 짝 |
| `retention` (`borrowed`, `retained`) | `Parameter` | 콜백 포인터를 native가 호출 뒤에도 보관하는가 |
| `injected` (`allocator`, `io`) | `Parameter` | shim이 채우는 인자. release 함수의 시그니처 판정에서 제외된다. |
| `return_semantic` (`c_string`, `utf8_string`) | `SemanticFn` | 문자열 반환의 전달 형태. caller-owned이면 c_string이어도 slice 경로를 탄다. |

lowering은 이것을 `AbiFn.release_symbol`, `slice_return_element`, `ret_string`,
`materialized_return`, `materialized_out`, `callback_slots`로 풀고, `Program.constructors`를 그대로
넘긴다. `boxed`와 `child_of_receiver`는 `origin`에서 다시 읽는다.

### 1.2 경로별 표

각 행은 semantic이 그 경로를 고르는 조건, lowering이 세우는 필드, 백엔드별 emit 함수, 오류나 부재
경로의 동작, 호출이 끝난 뒤 Go가 native 메모리를 들고 있는지, 그리고 그 경로를 통과하는 golden case를
적는다.

| # | 경로 | semantic 선택 조건 | lowering | emit (cgo / purego / shim) | 오류·부재 경로 | 호출 후 Go가 native 메모리를 보유 | golden case |
|---|---|---|---|---|---|---|---|
| 1 | 생성자 짝 handle | `ownership = caller`, 반환 `!*T`, `constructors[]`에 `T`의 init/deinit | 없음. emit이 `constructorForInit`으로 다시 찾는다. `ownedReturnIsWrappable`이 검증 | `common.writeOwnedHandleResult` → `newT(ptr, …)`; `public_types.zig`가 `runtime.AddCleanup(value, cleanupT, state)`, `Close`, `zigoAcquire/Release/Poison` 생성 | 오류 코드면 handle 없음. panic이면 poison되어 `Close`가 deinit 없이 누수 | 예. `Close` 또는 cleanup까지 | `complex`, `root_constructor`, `union_snapshot` |
| 2 | boxed 값 생성자 | `boxed = create`/`destroy`, `.allocator` 필수 | `origin.boxed` | shim `writeBoxedConstructor`가 `allocator.create` 뒤 값을 채우고, destroy 짝은 `allocator.destroy(self)`; Go 쪽은 1행과 같다 | 생성 중 Zig error면 shim이 `destroy` 후 코드 반환 | 예 | `injection` |
| 3 | receiver의 자식 handle | 1행 + `child_of_receiver = true`, `go_owner` | `origin.childOfReceiver()` | `newT(ptr, zigoChildParent)`; 부모에 자식 수 등록, 부모 `Close`는 `*HandleInUseError` | 자식 생성 실패면 부모 예약 해제 (`zigoChildCreated`) | 예. 부모보다 먼저 닫아야 한다 | `dependent_handle` |
| 4 | borrowed handle view | `borrowed_return = true`, 반환 `*T`/`?*T`/`!*T`/`!?*T`, receiver 필수 (ZIGO033–035) | 없음 | `*T` handle을 owner 사슬과 함께 만든다. destructor 없음, `Close`는 view만 분리 | 부재면 `nil, false` | 아니오. 부모가 소유 | `borrowed_return` |
| 5 | borrowed slice 반환 (복사) | `ownership = borrowed`, 반환 `[]T`/`![]T`/`?[]T`/`!?[]T` | `slice_return_element` | `raw.writeCgoSliceReturn` release 없이 복사 (`C.GoBytes`, `copy`, castable struct는 통째 `copy`); purego `writePuregoSliceReturn`; shim은 `out_result_ptr/len`에 native slice를 그대로 적는다 | 오류면 out 파라미터를 읽지 않음. 부재면 `nil, false` | 아니오. 호출 시점 사본 | `complex` `sampleValues`, `value_struct` `points`, `optional_slice` `digits` |
| 6 | caller-owned slice + release | 5행 + `ownership = caller`, `release` | `release_symbol` (함수 이름을 심볼로 해석) | cgo: 복사 후 `C.<release>(ptr, len)`; purego: 복사 후 `bindings().fn<release>(…)`; release 함수는 공개 API에서 숨긴다 (`lower.isReleaseTarget`) | 오류·부재면 복사도 release도 없음 | 아니오 | `complex` `takeSamples`, `optional_slice` `takeOwned`, `root_constructor` `render` |
| 7 | 문자열 반환 | `return_semantic = c_string` 또는 `utf8_string` | `ret_string`. caller-owned c_string은 `caller_owned_c_string`이 `.none`으로 내려 6행을 탄다 | borrowed c_string: `C.GoString` / `zigoCStringString` 복사, release 없음; utf8은 5행과 같음 | 5·6행과 같음 | 아니오 | `complex` `echoCString`, `optional_slice` `takeOwnedCString` |
| 8 | narrow int slice 반환 | 6행 + 원소가 C 폭보다 좁은 정수 (`abi.narrowSliceElement`) | `slice_return_element`의 narrow 원소 | shim `writeShimSliceReturn`이 native 버퍼 **안에서** `@constCast`로 원소를 승격 폭으로 다시 쓴 뒤 넘긴다; Go는 6행 | borrowed narrow slice 반환은 ZIGO018로 거부 | 아니오 | `narrow_int` `takeCodepoints` |
| 9 | narrow int slice 파라미터 | 파라미터 원소가 narrow 정수, `.allocator` 필수 (ZIGO045) | 없음 | shim `writeNarrowSliceSetups`가 임시 slice를 `allocator.alloc`하고 `defer free`; out 방향이면 결과를 되복사. release 대상 함수는 이 단계를 건너뛴다 (`isNarrowSliceReleaseTarget`) | — | 아니오 | `narrow_int` |
| 10 | materialized 결과 트리 | `.repr = .materialized` 타입을 반환·payload·slice·out으로 사용, `ownership = caller`, `release`가 `[]u8`을 받음 (ZIGO048) | `materialized_return`/`materialized_out` (+ `layout` 인덱스), `slice_return_element = u8`, `release_symbol` | shim `writeMaterializedReturn/Output`이 `ZigoMaterializedBuilder`로 버퍼를 만들어 `out_result_ptr/len`에 적음; Go는 6행의 byte 경로로 복사·release 후 `zigoDecode…Buffer` | 오류면 버퍼 없음. 빌더 OOM은 shim panic | 아니오 | `materialized` |
| 11 | retained 콜백 | `retention = retained` | `callback_slots`, `retainedCallbackOwner` | Go handle을 생성자 state 또는 receiver slot에 입양 (`zigoReplaceCallbackHandle`); cleanup과 `Close`가 `deleteCallbackHandle`, 교체 시 이전 handle 삭제 | 호출 실패면 입양 전 defer가 삭제 | 예. Go 콜백 handle을 native가 보관 | `callback_error`, `complex` |
| 12 | 스트림 파라미터 | `io_stream` | 없음 | 호출 범위 adapter. `defer deleteCallbackHandle` | — | 아니오 | `io_stream` |
| 13 | 값 반환 (extern/packed struct, snapshot, scalar) | 그 외 | `ret_struct`, `payload_struct`, snapshot | 값 복사. 소유권 없음 | — | 아니오 | `value_struct`, `packed_value`, `union_snapshot` |

### 1.3 같은 일을 다른 코드로 하는 자리

- **release 후보 찾기.** `validate/ownership.zig`의 `releaseCandidateParameter`가 이름으로 함수를
  찾아 `void` 반환과 노출 파라미터 하나를 요구하고, `validate/materialized.zig`의
  `materializedReleaseTargetIssue`가 같은 helper를 부르되 원소 규칙만 다르다. lowering은
  `lower.zig`의 별도 루프에서 이름을 다시 심볼로 해석하고, emit은 `raw.releaseFunction`이 심볼로
  다시 `AbiFn`을 찾는다. 한 사실을 이름, 심볼, `AbiFn` 세 형태로 세 번 해석한다.
- **복사 후 release.** cgo `writeCgoSliceReturn`과 purego `writePuregoSliceReturn`이 같은 순서(복사,
  release, 반환)를 따로 적는다. materialized는 그 위에 byte 원소로 한 번 더 얹힌다.
- **payload 벗기기.** `releasableSliceReturnElement`(소유권 질문), `sliceReturnElement`(호출 규약
  질문), `borrowedOpaqueReturn`, `ownedOpaqueReturn`이 각각 error union과 optional을 벗긴다. 답이
  다른 이유는 문서화되어 있지만(`abi.zig`의 `slice_return_element` 주석) 규칙이 네 곳에 있다.
- **"이 함수는 숨긴다".** release 대상은 `lower.isReleaseTarget`, 소멸자는 `constructorForDeinit`,
  둘 다 `emitsPublicFunction`이 합친다. `Must` 변형 규칙(`lower.mustVariant`)도 같은 두 조건을
  다시 나열한다.
- **누가 어떤 handle을 poison하는가**는 emit의 `renderHandleChecks`와 `zigoPoison` 생성 코드에
  있고 IR에는 없다.

### 1.4 관찰

- 소유권 이전이 일어나는 형태는 결국 셋이다. (a) handle: native 객체를 Go가 들고 있다가
  destructor로 돌려준다. (b) 버퍼: native가 준 메모리를 즉시 복사하고 release로 돌려준다.
  slice, C string, narrow slice, materialized가 모두 여기 속한다. (c) 토큰: Go 객체(콜백)를
  native가 들고 있다가 Go가 지운다. 나머지는 빌림 또는 값이다.
- (b)는 "복사 후 즉시 release"라는 한 정책만 있다. 사용자가 native 메모리를 Go에서 오래 들고
  있는 경로는 없으므로, `runtime.AddCleanup`이 필요한 것은 (a)와 (c)뿐이고 이미 그렇게 되어
  있다.
- `ownership = library`는 읽는 곳이 없다. 4절: 예약 값으로 문서화하고 남긴다.
- 검증은 형태별로 흩어져 있지만 모두 같은 질문을 한다. "이 함수의 결과를 누가, 무엇으로,
  언제 돌려주는가."

## 2. 설계

### 2.1 원칙

`semantic.json`은 그대로 두고, lowering이 1.1의 조각들을 읽어 함수마다 하나의 소유권 레코드를
세운다. emit과 validate는 레코드만 읽는다. 이는 계획 109가 `must_variant`와
`reaches_callback_errors`에 적용한 규칙과 같다. IR 파일 계약을 바꾸지 않으므로 `ir_version`도,
`abi-diff`도 바뀌지 않는다. `Semantic.parse`는 모르는 필드를 거부하므로(`parseFromValue` 기본
옵션) 새 semantic 필드는 그 자체로 호환성 사건이고, 이 설계는 그 비용을 치르지 않는다.

### 2.2 레코드

```zig
// abi.zig
pub const Ownership = union(enum) {
    /// 값, void, 스칼라. 넘길 메모리가 없다.
    none,
    /// receiver가 소유하는 native 객체를 가리키는 view. (표 4행)
    borrowed_view: struct { handle: []const u8 },
    /// native slice를 호출 시점에 복사한다. 부재 형태는 Go 시그니처가 정한다. (5, 7행)
    borrowed_copy: struct { element: semantic.TypeNode, text: StringRole, absent: bool },
    /// Go가 destructor까지 들고 있는 native 객체. (1, 2, 3행; 11행의 슬롯)
    handle: struct {
        type_name: []const u8,
        destructor: []const u8, // 심볼
        boxed: bool,
        child_of_receiver: bool,
        retained_slots: usize,
    },
    /// native가 준 버퍼를 복사하고 곧바로 돌려준다. (6, 7, 8, 10행)
    buffer: struct {
        element: semantic.TypeNode,
        release: []const u8, // 심볼
        release_receiver: ?[]const u8,
        narrow: bool,
        materialized: ?usize, // layout 인덱스
        absent: bool,
        fallible: bool,
    },
};

pub const ParamOwnership = enum { transient, retained_token, staged_copy, stream };
```

`AbiFn.ownership: Ownership`과 `AbiFn.param_ownership: []const ParamOwnership`이 새 필드다.
기존 필드(`release_symbol`, `slice_return_element`, `ret_string`, `materialized_return`,
`materialized_out`, `callback_slots`)는 레코드가 자리를 잡은 뒤 하나씩 지운다.

### 2.3 인벤토리 행의 매핑

| 표 행 | 레코드 | 생성물 변화 |
|---|---|---|
| 1 생성자 짝 | `handle{ boxed=false, child=false }` | 없음 |
| 2 boxed | `handle{ boxed=true }` | 없음. shim의 `create`/`destroy`는 `origin.boxed`를 계속 읽어도 된다 |
| 3 자식 handle | `handle{ child_of_receiver=true }` | 없음 |
| 4 borrowed view | `borrowed_view` | 없음 |
| 5 borrowed slice | `borrowed_copy` | 없음 |
| 6 caller-owned slice | `buffer{ narrow=false, materialized=null }` | 없음 |
| 7 문자열 | borrowed는 `borrowed_copy{ text=c_string }`, caller-owned는 `buffer{ element=u8 }` | 없음. `caller_owned_c_string` 특례가 레코드 생성 한 곳으로 모인다 |
| 8 narrow 반환 | `buffer{ narrow=true }` | 없음 |
| 9 narrow 파라미터 | `param_ownership = staged_copy` | 없음 |
| 10 materialized | `buffer{ element=u8, materialized=layout }` | 없음 |
| 11 retained 콜백 | `param_ownership = retained_token` + `handle.retained_slots` | 없음 |
| 12 스트림 | `param_ownership = stream` | 없음 |
| 13 값 | `none` | 없음 |

모든 행이 생성물 변화 없이 매핑된다. 유일하게 매핑되지 않는 것은 `ownership = library`인데,
읽는 곳이 없으므로 레코드도 `none`으로 두고 문서에서 "예약됨"으로 적는다.

### 2.4 레코드가 대신하는 코드

- **validate.** `releaseTargetIssue`(ZIGO016), `materializedReleaseTargetIssue`(ZIGO048),
  `ownedReturnIsWrappable`(ZIGO015)이 각자 하던 "release 후보 찾기"를
  `lower.releaseTarget(document, function) ?ReleaseTarget` 하나로 모은다. 레코드 생성 자체는
  검증 뒤에 돌아야 하므로 validate는 레코드가 아니라 이 helper를 읽는다.
- **lower.** `release_symbol` 해석 루프, `returnStringRole`, `sliceReturnElement`,
  `abi.materializedReturn/Out`이 레코드 생성 함수 `ownershipOf` 안으로 들어간다.
- **emit.** `raw.writeCgoSliceReturn`과 `purego.writePuregoSliceReturn`의 release 분기는
  `ownership == .buffer`를 묻고, materialized의 byte 특례는 `buffer.materialized`로 대체된다.
  `common.writeOwnedHandleResult`와 handle 생성기는 `handle` 변형을 읽는다.
  `common.releaseReceiverCName`은 `buffer.release_receiver`가 된다.

### 2.5 동기가 된 두 기능의 평가

**자동 `runtime.AddCleanup`.** 인벤토리 1.4가 보여주듯 Go가 호출 뒤에도 native 메모리를 드는
형태는 handle과 retained 콜백 토큰뿐이고, 둘 다 이미 생성자 state를 통해 cleanup에 등록된다.
버퍼 계열은 "복사 후 즉시 release"라 등록할 것이 없다. 따라서 이 기능은 새 코드가 아니라
레코드의 불변식이다. `handle`과 `retained_token`만 cleanup 대상이고, 새 소유권 변형을 추가하는
사람은 이 둘 중 하나로 표현하거나 복사 정책을 따라야 한다. 복사를 없애는 "native 메모리 위의
zero-copy view"는 이 불변식을 깨는 새 기능이고, GC가 보지 못하는 포인터를 Go slice에 싣는
문제와 `bindings.md`가 약속한 "반환 slice는 항상 Go 메모리" 계약을 모두 건드린다. 벤치마크가
복사 비용을 문제로 증명하기 전에는 하지 않는다.

**arena 스코프 API.** 모든 버퍼가 호출마다 release되므로 arena가 줄일 수 있는 것은 release
호출 횟수뿐이다. 호출 하나에 경계 통과 하나가 붙는 구조에서 이는 작은 slice를 루프에서 많이
반환하는 API에만 의미가 있고, 그 API는 이미 `...Into(dst)` out 파라미터 패턴으로 복사와
release를 모두 피할 수 있다. Zig 쪽 arena를 handle로 노출해 주입 allocator 자리에 넣는 형태는
C 시그니처가 바뀌는 새 기능이며, 레코드에는 `buffer.release`가 심볼이 아니라 "arena handle에
귀속"이 되는 새 release 종류가 필요하다. 레코드가 있으면 그 변형 하나를 더하는 일이 되므로,
순서는 레코드가 먼저다. 근거는 계획 68이 `LockOSThread`에 적용한 기준과 같다. 측정된 이득이
호출 비용의 10%를 넘지 않으면 ABI를 바꾸지 않는다.

### 2.6 호환성

- `semantic.json` 변화 없음, `ir_version` 유지, golden 44개 바이트 동일이 각 phase의 완료 조건이다.
- `abi-diff`는 semantic 필드를 비교하므로 바뀌지 않는다. 다만 지금 "release function changed"와
  "return ownership or semantics changed"를 따로 보고하는데, 레코드가 생기면 두 변경을 레코드
  비교 한 번으로 묶을 수 있다. 보고 문구가 바뀌므로 선택 사항으로 남긴다.
- `ownership = library`는 생성기가 읽지 않으므로 제거해도 생성물은 같다. 그러나 필드 값이
  사라지면 그 값을 적은 옛 `semantic.json`이 파싱에 실패하므로 enum 값은 두고 문서만 고친다.

## 3. 권고

**채택한다. 단 lowering 레코드로만 도입하고 IR 파일 계약은 건드리지 않는다.** 소유권은 이미
세 형태(handle, buffer, token)로 수렴해 있고, 흩어진 것은 그 형태를 다시 알아내는 코드다.
레코드는 그 코드를 한 곳으로 모으며 생성물을 바꾸지 않는다.

`runtime.AddCleanup` 자동화는 이미 완성된 상태이므로 별도 작업이 없다. arena 스코프 API는
레코드 이후로 미루고, 필요가 측정으로 입증될 때 별도 계획으로 설계한다.

### 후속 계획 초안 (4 phase, 모두 golden 불변)

1. `abi.Ownership`과 `lower.ownershipOf` 추가, `AbiFn.ownership`/`param_ownership` 기록. golden
   case마다 기대 레코드를 단언하는 lower 테스트를 추가한다. emit 변경 없음.
2. emit이 레코드를 읽는다. cgo와 purego의 복사 후 release 분기, materialized byte 특례,
   `releaseReceiverCName`, `writeOwnedHandleResult`를 옮기고 대체된 `AbiFn` 필드를 지운다.
3. validate가 `lower.releaseTarget`을 읽는다. ZIGO015/016/048의 후보 찾기를 한 helper로 모으고,
   payload를 벗기는 네 함수를 `TypeNode.errorPayload` 위의 두 개(소유권 질문, 호출 규약 질문)로
   줄인다.
4. `ownership = library`를 "예약됨"으로 문서화하고, `01-architecture.md` 9절의 세 축 설명을
   레코드 기준으로 고친다.

## 4. 구현 결과

계획 `111-ownership-record`가 2절의 설계를 lowering 레코드로 구현했다. `semantic.json`과
생성물은 바뀌지 않았다.

- `abi.Ownership` (`none`, `borrowed_view`, `borrowed_copy`, `handle`, `buffer`)과
  `abi.ParamOwnership` (`transient`, `retained_token`, `staged_copy`, `stream`)이
  `AbiFn.ownership`, `AbiFn.param_ownership`에 기록된다. `lower.ownershipOf`가 검증된 문서
  위에서, 모든 함수의 심볼과 handle 슬롯 수가 정해진 뒤 마지막으로 세운다.
- 2.2의 초안과 다른 점: `buffer.release`는 심볼이 아니라 `Program.functions` 인덱스다.
  purego는 release 함수의 Go 이름을, cgo는 심볼을 필요로 하므로 둘 다 인덱스에서 읽는다.
  receiver는 C typedef 이름(`release_receiver_c_name`)으로 바로 적는다. `handle.destructor`도
  심볼이다.
- release 후보 찾기는 `lower.releaseTarget` 하나다. ZIGO016, ZIGO048, `ownershipOf`가 같은
  함수를 부른다. 검증은 promotion 전 함수 표 위에서 돌고 lowering도 그 표(`source_document`)로
  release를 해석한다. promotion이 receiver를 가진 release 메서드에 합성 error union을 붙이면
  `void` 반환 조건이 깨지기 때문이다.
- payload 벗기기는 `lower.releasableSliceReturnElement`(소유권 질문, optional까지 벗김)와
  `lower.sliceReturnElement`(호출 규약 질문) 둘이며 모두 `TypeNode.errorPayload` 위에 있다.
- 지운 것: `AbiFn.release_symbol`, `raw.releaseFunction`, `common.releaseReceiverCName`,
  `validate.releaseCandidateParameter`, `validate.constructorDeinitFor`.
- 남긴 것: `ret_string`, `slice_return_element`, `materialized_return`, `materialized_out`은
  C 시그니처 모양을 말하는 호출 규약 필드라 그대로 둔다. `ownership = library`는 enum 값만
  남긴 예약 값이며 생성기는 읽지 않는다. 옛 `semantic.json`이 파싱되도록 값은 제거하지 않는다.
