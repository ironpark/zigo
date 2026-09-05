---
depends_on:
- "112-112-explicit-interfaces#1"
perf_phase: false
status: planned
---
> DONE-WHEN: `zig build test` 녹색. 기존 golden 44개 불변, 새 golden 2개가 `go vet` 단계를 통과한다.
> NEXT: none

# Lowering, signature rule and emitter

## Planned Work

- `public.renderPublic`의 메서드 헤더 렌더링(파라미터 목록과 반환 타입)을
  `public_writers.writeMethodSignature(scope, allocator, writer, program, function, go_names)`로
  뽑는다. golden 불변.
- `abi.AbiInterface { name, doc, closer, package, methods: []Method { zig_name, functions: []*const AbiFn } }`,
  `Program.interfaces`. lowering이 `Semantic.interfaces`를 해석한다(receiver가 타입인 함수 찾기).
- `emit/interfaces.zig`: `signatureMismatch(allocator, program) !?Mismatch`가 각 메서드의 시그니처
  문자열(`Must` 변형 여부 포함)을 타입별로 렌더링해 첫 불일치를 돌려준다. `generator.generate`가
  lowering 뒤 이를 불러 ZIGO049 "method `m` has signature `A` on `X` but `B` on `Y`"로 보고한다.
- `renderInterfacesFile`이 `<pkg>_interfaces_gen.go`를 낸다: doc, "implemented by *A and *B" 줄,
  메서드(첫 타입 메서드 doc), `Must` 변형, `io.Closer`, 단언 두 줄. 인터페이스가 없으면 파일도 없다.
  `appendPublicPackage`가 union 파일 옆에서 부른다. 하위 패키지는 `package` 필드로 거른다.
- golden case `interfaces`(cgo)와 `interfaces_purego`: 두 opaque handle과 공통 메서드, 생성자 짝,
  `Must` 변형이 있는 메서드 하나, `.closer = false` 인터페이스 하나.

## Done When

- `zig build test` 녹색. 기존 golden 44개 불변, 새 golden 2개가 `go vet` 단계를 통과한다.
- 시그니처 불일치 문서에 대한 generator 테스트가 ZIGO049를 받는다.
