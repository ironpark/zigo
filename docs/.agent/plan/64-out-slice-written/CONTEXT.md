# SCOPE

- `src/reflect/walk.zig`: `param_meta.written` 반영.
- `src/gen/ir/semantic.zig`: `Parameter.written` 필드, 직렬화·역직렬화(기본값 `.all`, 필드 없는 옛 JSON 호환).
- `src/gen/validate.zig`: `ZIGO017` — `.written`은 `.direction = .out`에만, 반환 타입은 `usize`/`!usize`만.
- `src/gen/abi_diff.zig`: `written` 변경은 `.compatible`.
- `src/gen/emit.zig`: shim의 `_written` 대입, 공개·raw 계층의 슬라이스 마샬링(캐스트 경로, out 무복사 진입, `written` 만큼 되돌리기), Go 쪽 레이아웃 가드 생성, `isCountReturn` 휴리스틱을 명시 메타데이터로 대체.
- `tests/generator_cases/*`: fixture와 골든. `src/gen/*.zig` 단위 테스트.
- `examples/07-event-queue`: `estimate`에 `.written = .return`, `readInto`류 `…Into(dst)` 추가, cgo·purego 테스트.
- 문서 세 편.

# CONTEXT

## Current implementation and bottlenecks

- 방향: `src/gen/ir/semantic.zig:226-238` (`Direction`, `Parameter`), 반영 `src/reflect/walk.zig:158-163`. `.out` 검증은 없다. lowering `src/gen/lower.zig:107-129`이 `_ptr`/`_len` 뒤에 `.slice_written` 역할의 `*usize`를 붙인다.
- shim: `writeSliceWrittenAssignments` `src/gen/emit.zig:623-629`가 `{p}_written.* = {p}_len` 을 무조건 기록. 호출 지점 `:223`(에러 유니온 성공 경로), `:235`(void). 반환이 plain `usize`인 함수는 호출조차 안 된다(`return` 뒤라서). 오류 경로에서는 대입이 없다.
- cgo raw: `src/gen/emit.zig:1075-1099` `make([]C.x)` + 원소별 진입 변환(out에도), `:1183-1196` `Written`만큼 원소별 복귀. 스칼라 슬라이스(`:1100-1108`)는 Go 슬라이스 주소를 직접 넘기고 복귀 복사가 없다.
- purego raw: `:1966-1970`, `:2016-2019` — `[]TData` 주소를 직접 넘긴다. 즉 `TData` 미러(명시 패딩 포함)가 C 레이아웃 그 자체다. 두 백엔드의 aliasing 동작이 다르다.
- 공개 계층: `zigo<T>SliceToRaw`/`SliceFromRaw`/`SliceCopyFromRaw` `:2919-2931`, out 복귀 `writePublicValueStructSliceCopyBacks` `:2381-2396`. `isCountReturn` `:2377`이 반환이 `usize`면 `int(result)`, 아니면 `len(name)`으로 자른다 — shim과 다른 수로 두 번 자르는 암묵 규칙.
- 공개 struct는 Go 네이티브 타입(`bool`, enum 타입, `int32`…)이고 `TData`는 C 폭 + 명시 패딩 (`tests/generator_cases/value_struct/expected/internal/raw/raw_gen.go` `ConfigData`). Go 쪽 레이아웃 단정은 생성물 어디에도 없다. Zig 쪽은 `zigoAbiGuard`(`emit.zig:251-294`)가 `@sizeOf`/`@alignOf`/`@offsetOf`를 comptime으로 고정한다.
- `ZIGO012` `src/gen/validate.zig:186-194`: 필드를 bool·정수·실수·등록 enum·중첩 extern struct로 제한. 최고 코드 `ZIGO016`, 다음은 `ZIGO017`. 진단은 `validate.zig` 인라인이다.
- `abi_diff`: `signatureEqual` `src/gen/abi_diff.zig:172-179`가 `direction`/`semantic`/`type` 변화를 모두 breaking으로 본다. `ChangeKind = { breaking, added, compatible }`.
- 현재 `.out` 사용처는 `examples/07-event-queue/src/bindings.zig:53-57`(`EventQueue.estimate`, `root.zig:216`)와 `tests/generator_cases/value_struct/semantic.json:38`(`fillPoints`) 뿐. `Config` fixture는 bool 필드를 가지므로 캐스트 경로 대상이 아니다 — 새 fixture가 필요하다.
- 문서: `docs/bindings.md:66-77`(함수 메타데이터 표), `:111-123`(슬라이스 반환 소유권), `:310-349`(extern struct 값, `:345-349`는 "native가 기록한 개수만큼 복사"라고 적혀 있으나 shim 구현과 다르다), `docs/limitations.md:58-100`, `docs/generated-code.md:116-131`.

## Target structure and invariants

- 캐스트 적격 타입: `ZIGO012`를 통과하고 재귀적으로 bool 필드가 없는 extern struct. enum 필드는 backing 정수가 같으면 적격. 적격성 판단은 emit.zig의 한 predicate에 두고 공개·raw·양 백엔드가 같은 predicate를 쓴다.
- Go 쪽 레이아웃 가드: 공개 패키지(struct 파일)에 공개 `T`와 `raw.TData`의 `unsafe.Sizeof`·`unsafe.Offsetof`가 같음을 컴파일 시점 단정(`var _ = [1]struct{}{}[unsafe.Sizeof(T{})-unsafe.Sizeof(raw.TData{})]` 류, 필드마다 하나)으로 고정한다. cgo raw 파일에는 `TData`와 `C.x`의 크기 단정을 추가해 Zig 가드 → 헤더 → `C.x` → `TData` → `T` 사슬이 닫히게 한다. 가드는 적격 타입에만 생성한다(bool struct는 캐스트하지 않으므로 필요 없음).
- 캐스트 경로: 공개 계층은 `unsafe.Slice((*raw.TData)(unsafe.Pointer(&values[0])), len(values))`로 `[]T` → `[]TData` 재해석(빈 슬라이스는 nil), raw cgo는 `(*C.x)(unsafe.Pointer(&values[0]))`를 넘긴다(purego와 동일). 진입·복귀 복사 루프와 `SliceToRaw`/`SliceCopyFromRaw` 호출이 사라진다. raw API 시그니처(`[]TData`)는 유지해 공개 계층 변경을 최소화한다.
- 복사 경로(bool struct): `.out`이면 진입 변환 대신 `make([]TData, len)` 만 하고, 복귀는 `written` 만큼만.
- `.written` 의미: `.all`(기본, 현 shim 동작 유지 — `_written = len`), `.return`(shim이 성공 경로에서 `_written = result`, 오류 경로 0). `.return`은 반환 payload가 `usize`가 아니면 `ZIGO017`. `isCountReturn` 휴리스틱은 제거하고 `.written`이 유일한 규칙이 된다 — `.all`인 usize 반환 함수는 앞으로 `len` 전부 되돌아온다(07-event-queue `estimate`는 `.return`으로 바꾼다).
- plain(non-error, non-void) 반환 함수에서도 `_written` 대입이 나가도록 shim을 `const result = …; written 대입; return result` 형태로 정리한다.
- `semantic.json` 파라미터에 `written` 필드 추가(`"all"`/`"return"`). 역직렬화는 필드 부재를 `.all`로 본다. `abi_diff`는 `written` 차이를 `.compatible` "parameter written hint changed"로 보고한다.
- 문서 계약: "out slice의 `written` 이후 원소는 호출 전 값 그대로" — `io.Reader`와 같은 모양. "큰 결과는 out 파라미터로 받아라"를 권장 패턴으로.
