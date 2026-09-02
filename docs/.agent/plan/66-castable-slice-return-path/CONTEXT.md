# SCOPE

- `src/gen/emit.zig`: `:2572`(에러 유니온 payload), `:2742`(직접 반환), `:4307`(tagged union payload) 세 출력 지점에서 `isCastableStruct`(계획 64가 만든 predicate)로 분기. `:3143` `SliceFromRaw` 도우미 생성 조건. `renderPublic`의 손으로 쓴 import 블록에 `unsafe` 조건.
- `tests/generator_cases/value_struct` 골든, `emit.zig` 단위 테스트(`:5692` 부근 기존 단정 옆).
- 예제 재생성. `docs/generated-code.md`.

# CONTEXT

## Current implementation and bottlenecks

- raw cgo `Points()`(`raw_gen.go:154-162`): `make([]PointData)` + `copy(unsafe.Slice(...))` — 한 번 복사한 새 할당을 반환. purego도 같은 모양.
- 공개 `Points()`(`config_gen.go:89`): `return zigoPointSliceFromRaw(raw.Points())` — `config_structs_gen.go:60`의 도우미가 `make([]Point)` 후 원소별 변환. 두 번째 할당과 복사.
- 적격 타입에는 `config_structs_gen.go:36` 류의 `[1]struct{}{}[unsafe.Sizeof(T{})-unsafe.Sizeof(raw.TData{})]` 크기·오프셋 가드가 이미 있다.
- 공개 계층은 파라미터 방향에서 이미 `unsafe.Slice((*raw.PointData)(unsafe.Pointer(&values[0])), len(values))`(`config_gen.go:43`)를 쓴다. 반환은 반대 방향 캐스트일 뿐이다.

## Target structure and invariants

- 적격 원소 반환: `result := raw.Points(); if len(result) == 0 { return nil }; return unsafe.Slice((*Point)(unsafe.Pointer(&result[0])), len(result))`. 도우미 하나(`zigo{T}SliceView(values []raw.TData) []T` 등)로 묶어 세 출력 지점이 같은 이름을 부르게 한다. 도우미 이름은 "복사하지 않음"이 드러나야 한다.
- raw 소유 할당을 그대로 공개하므로 GC 관점에서 안전(Go 힙). `.returns = .caller` 경로는 raw가 native 버퍼를 복사한 뒤 release하는 현 구조를 유지하고 그 결과를 재해석한다 — 순서(복사 → release → 재해석)를 테스트로 고정.
- 비적격 타입은 `SliceFromRaw` 유지. 적격 타입은 `SliceFromRaw`를 생성하지 않는다(`SliceToRaw`·`SliceCopyFromRaw`의 계획 64 처리와 같은 방식).
