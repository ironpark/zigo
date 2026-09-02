# GOALS

## Problem and the end result from the user's point of view

계획 64 이후 캐스트 적격(bool 필드 없는) extern struct 슬라이스는 파라미터 방향에서 복사 없이 넘어가고, raw 계층의 슬라이스 반환도 `make` + `copy` 한 번으로 줄었다. 그러나 공개 계층은 여전히 `zigo{T}SliceFromRaw(raw.Points())`로 `[]raw.TData` → `[]T`를 원소별로 다시 복사한다(`tests/generator_cases/value_struct/expected/config/config_gen.go:89,101`). raw가 이미 소유한 새 할당이므로 그 메모리를 `[]T`로 재해석하면 두 번째 복사와 두 번째 할당이 사라진다. 레이아웃 동일성은 계획 64가 만든 Go 쪽 컴파일 시점 가드가 보증한다.

작업 후: 캐스트 적격 원소의 슬라이스 반환(borrowed 복사 반환, `.returns = .caller` 반환, 에러 유니온 payload, tagged union payload)은 공개 계층에서 할당·복사 없이 raw의 결과를 재해석해 돌려준다. "반환 슬라이스는 핸들 수명과 독립"이라는 복사 계약은 그대로다(복사는 raw 계층에서 한 번 이미 일어난다).

## Measurable goals

- 캐스트 적격 원소의 슬라이스 반환 공개 골든에 `zigo{T}SliceFromRaw(` 호출이 없고 `unsafe.Slice((*T)(unsafe.Pointer(&result[0])), len(result))` 재해석이 있다.
- 비적격(bool) 원소는 `SliceFromRaw` 경로를 유지한다.
- 쓰이지 않게 된 `zigo{T}SliceFromRaw` 도우미는 적격 타입에서 생성되지 않는다(dead code 없음).

## Supported scope and non-goals

지원: 공개 계층의 struct 슬라이스 반환 경로 전부(`emit.zig:2572`, `:2742`, `:4307`), cgo·purego 양 백엔드(공개 계층은 백엔드 공통).
비목표: raw 계층의 복사 제거(핸들 수명 독립 계약 유지), bool 원소 struct, 스칼라 슬라이스(이미 raw가 복사 한 번), 뷰 반환.

## Reference source / commit / license

- 계획 64 완료 보고에서 에이전트가 남긴 후속 제안. 저장소 내부 작업.

## Completion criteria for the whole plan

- 위 측정 목표 테스트 통과, `zig build test`, 예제 10개 cgo·purego 4개 `go-check`·`go test` 통과.
- `docs/generated-code.md`의 슬라이스 반환 설명에 "적격 struct는 공개 계층에서 재해석" 한 줄 추가.
