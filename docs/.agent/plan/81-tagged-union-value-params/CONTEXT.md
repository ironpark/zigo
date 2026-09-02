# SCOPE

- 적격성 판정 함수(모든 payload가 scalar/void)와 ZIGO006 힌트 분리.
- C ABI: `tag`(정수) + payload마다 슬롯 하나(같은 타입의 payload는 슬롯 공유 가능하나 단순함을 위해 variant마다 슬롯). shim이 tag로 분기해 union 값을 만든다.
- Go: `type ScrollViewport struct { tag; fields }` + variant 생성자 + `Tag()`. 값이므로 handle 검사 없음.
- 예제 10에 값 파라미터 함수 추가, cgo·purego 골든.
- 문서: `docs/bindings.md`(tagged union 절에 값 파라미터), `docs/limitations.md`, CHANGELOG.

# CONTEXT

## Current implementation and bottlenecks

- tagged union은 `.repr = .tagged_union` 등록 후 pointer(handle)로만 오가며 snapshot/projection으로 읽는다. 파라미터 자리에는 어떤 형태로도 올 수 없다.
- ZIGO006은 세 곳에서 나며 같은 힌트를 쓴다.

## Target structure and invariants

- 값 파라미터는 handle과 무관하다: 소유권·poison 없음, 복사로 전달.
- 슬롯 평탄화는 결정적이며 abi_diff는 variant 추가를 breaking으로 본다(C 시그니처가 늘어남).

## Implementation deviations

- 한 등록 union을 pointer handle과 값 파라미터로 동시에 쓰면 공개 Go 타입 이름과 method
  surface가 충돌하므로 ZIGO006으로 거부한다. 값 전달이 필요하면 scalar-payload union을
  별도 타입으로 등록한다. value-only union에는 handle/projection 파일을 생성하지 않는다.
- 값 payload 정수는 현재 C scalar 하강이 직접 지원하는 8/16/32/64비트와
  `isize`/`usize`로 제한한다. 임의 폭 정수 승격은 union payload slot에는 적용하지 않는다.
