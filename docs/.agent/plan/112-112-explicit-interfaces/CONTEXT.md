# SCOPE

새 semantic 필드 `interfaces`, 새 진단 ZIGO049, 새 emitter 하나, abi-diff 규칙, 문서.
기존 생성물은 바뀌지 않는다.

# CONTEXT

## Current implementation and bottlenecks

- reflector(`walk.zig` `reflect`)는 `.types`, `.functions`, `.packages`를 읽고 `Semantic`을 만든다.
  `.interfaces`는 없다.
- `Semantic.parse`는 모르는 필드를 거부한다. `emit_null_optional_fields = false`라 optional 필드는
  `null`이면 파일에 나타나지 않는다.
- 공개 메서드 시그니처는 `public.renderPublic`의 함수 루프 안에서 인라인으로 렌더링된다. 시그니처만
  따로 문자열로 얻는 함수가 없다.
- 검증(`validate.findIssue`)은 lowering 전 `Semantic` 위에서 돈다. lowering 뒤 emit 표면을 보는
  검사는 `validate.findMustVariantIssue`처럼 별도 진입점이며 `generator.generate`가 순서대로 부른다.
- 생성기가 Go 인터페이스를 내는 자리는 `public_types.renderUnionFile` 하나다. 파일 이름은
  `publicConcernPathAlloc`의 `<package>_<concern>_gen.go` 규칙을 따른다.

## Target structure and invariants

- `semantic.Interface { name, doc, methods, types, closer, package }`, `Semantic.interfaces: ?[]const Interface`.
- `abi.Program.interfaces: []const AbiInterface`, 메서드마다 타입별 `*const AbiFn`을 lowering이 해석한다.
- ZIGO049 규칙 1~3, 5, 6은 `validate/interfaces.zig`에서 규칙 표에 들어가고, 규칙 4(시그니처 동일)는
  lowering 뒤 `emit/interfaces.zig`가 `public_writers.writeMethodSignature`로 렌더링한 문자열을
  비교해 보고한다. 같은 writer가 인터페이스 본문을 낸다.
- 불변식: 인터페이스는 공개 패키지 표면만 바꾼다. cgo와 purego의 생성물은 인터페이스 파일에서 같다.
