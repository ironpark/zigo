# SCOPE

- `walk.zig`: `typeNode`가 `types` 목록(이미 방출된 TypeDecl)을 `zig_path` 문자열로 찾는 대신, comptime 등록 목록(`declaration.types`)에서 `entry.type == T`로 이름을 얻고 그 이름으로 TypeDecl을 찾는다. 등록되지 않은 타입은 지금처럼 `@typeName` fallback. callback 타입(`callbackNameForPath`)도 같은 원칙.
- semantic.json: `zig_path`가 같은 등록 타입이 둘 이상이면 `zig_path`에 등록 이름을 덧붙이거나(`"<typeName>#<name>"`) 생략해 유일성을 보장한다. `report`의 `Zig …` 표시와 abi_diff가 이를 다루는지 확인.
- 진단: 같은 `@typeName`을 가진 두 등록 타입이 서로 다른 타입이면 허용(정상), 같은 타입을 두 이름으로 등록하면 기존 진단 유지.
- `validate.zig`: enum tag 검사는 `<Type><Pascal(tag)>`를 검사한다. `label`/`spelling` 구조를 유지하되 `check.convert`가 접두 포함 변환을 하도록 한다. 숫자 시작 tag 골든 추가.
- 문서: `docs/bindings.md`(comptime enum 등록 안내), `docs/limitations.md`(ZIGO021 문구), CHANGELOG.

# CONTEXT

## Current implementation and bottlenecks

- `typeNode`는 파라미터/반환 타입 `T`를 만나면 `types` 목록에서 `zig_path == @typeName(T)`인 TypeDecl을 찾는다. comptime 생성 타입은 `@typeName`이 `vt.lib.Enum([_][]const u8{ "block", "bar" }[0..4])`처럼 잘려 tag 개수가 같으면 문자열이 같다.
- 등록 목록(`declaration.types`)에는 실제 comptime 타입 값이 있으므로 `entry.type == T` 비교가 가능하다. `receiverNameAt`은 이미 이 방식을 쓴다.
- `validate.zig` 식별자 검사는 enum tag를 `naming.pascalAlloc(tag)` 단독으로 판정한다.

## Target structure and invariants

- 등록 타입의 identity는 comptime 타입이다. `zig_path`는 진단·report용 표시이며 identity로 쓰지 않는다.
- semantic.json에서 `TypeDecl.name`은 유일하고, `TypeNode.ref`는 항상 `name`을 가리킨다(지금도 그렇다). 바뀌는 것은 ref를 정하는 방법뿐이다.
- 식별자 검사는 "실제로 emit되는 철자"를 검사한다. enum 상수는 `<Type><Pascal(tag)>`, 필드는 `Pascal(field)`, 함수는 `Pascal(name)`.
