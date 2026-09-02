# SCOPE

- `src/gen/validate.zig`: `supported()`를 `findIssue` 안의 진단으로 흡수, `integerSupported` 완화.
- `src/gen/lower.zig:680-685`: ABI 폭 승격, 원 폭 보존.
- `src/gen/emit.zig`: `writeTargetCall`(`:533-560`) 진입 범위검사·`@intCast`, `writeZigReturnConversion`(`:643-649`) 반환 `@intCast`, `rawGoNameAlloc`(`:5188`)·`callbackTypeBaseNameAlloc`(`:5154`) 세그먼트 Pascal 결합.
- `src/reflect/walk.zig`: N단계 경로 해석, `containerHasPath` 재귀, `.discover` 옵트인.
- `src/reflect/names.zig:184-238`: 중첩 컨테이너의 lexical 경로를 이어 붙여 `functionOwner`와 대조.
- `src/gen/naming.zig:45-59`: 세그먼트별 snake 후 `_` 결합.
- `src/gen/abi_diff.zig`: 필요 시 이행 허용.
- 문서 세 편, 골든·예제.

# CONTEXT

## Current implementation and bottlenecks

- `receiver`와 `namespace`(`src/gen/ir/semantic.zig:250-265`)는 상호 배타적 단일 문자열이다(`walk.zig:185`). 하류는 모두 `receiver orelse namespace`를 `owner` 하나로 접는다: 심볼(`naming.functionSymbolAlloc`, `walk.zig:189`, `lower.zig:201-206`), Go 이름(`rawGoNameAlloc` — 네임스페이스 함수는 `OwnerFuncName` 최상위 함수), shim 호출(`emit.zig:526-533` `target.{owner}.{name}` — 점 있는 경로여도 유효한 Zig), identity(`abi_diff.zig:227-242`), doc 수집(`names.zig:212,238`).
- 정수: `semantic.Int{bits, signed, is_usize}`(`semantic.zig:3-9`), `bits`가 JSON에 직렬화된다(`:97-99`). lowering이 `abi.AbiScalar{ .unsigned_int = bits }`로 폭을 그대로 넘겨 `uint{bits}_t`·`uint{bits}`를 찍으므로(`emit.zig:4855, 4747, 4952`) 검증이 hard reject한다.
- 범위 초과 보고: 함수별 오류 코드는 선언된 Zig error set에서만 나온다(`writeErrorSwitch` `emit.zig:640`). error union이 없는 함수에는 sentinel 자리가 없다. `-2`(`emit.zig:429`)는 패닉 longjmp 경로다. 패닉 브리지 `{prefix}_panic_bridge`/`{prefix}_last_error_message`(`emit.zig:409-418`)는 Go에서 `NativePanicError`로 나온다.
- 진단: `Diagnostic{severity, code, message, site: Site{path, declaration}, hint}`(`diagnostic.zig:5-27`), `findIssue`(`validate.zig:51+`)가 ZIGO001-017을 낸다. `Site.path`는 모두 `"semantic.json"` 고정. bare error 반환: `validate.zig:7 UnsupportedIrVersion`, `:8,:11 InvalidName`, `:641,:642,:649` `supported()`; `walk.zig:371,375 GenericCallback`, `:385,420 MissingOpaqueType`(어느 파라미터인지 없음); `@compileError`(`walk.zig:393-408, 419, 483, 487`)는 제약은 말하지만 함수·파라미터를 안 말한다.

## Target structure and invariants

- 경로: `root.` 접두를 떼고 마지막 세그먼트 전까지 `@field(Container, seg)`로 따라간다(세그먼트가 `type`이어야 함). 첫 세그먼트만 등록 `.types` 조회 fallback. `namespace`는 점으로 이은 경로(`"unicode"`, `"a.b.c"`)를 담는다 — 스키마 변경 없음, identity는 자연히 `a.b.c.fn`. 심볼은 세그먼트별 snake `_` 결합(`zg_unicode_codepoint_width`), Go 이름은 세그먼트별 Pascal 결합(`UnicodeCodepointWidth`). 기존 1단계 네임스페이스는 결과가 그대로여야 한다(골든 불변). `.discover = .public`은 그대로 1단계, `.discover = .recursive`(이름은 구현 시 결정) 옵트인으로 중첩 컨테이너 재귀.
- 정수: 검증은 `1 <= bits <= 64`만 본다. lowering이 `abi_bits = max(8, ceilPowerOfTwo(bits))`를 ABI 폭으로, 원 `bits`를 함께 보존. 헤더·Go는 승격 폭. shim 진입: 승격 폭 값이 원 폭 범위 밖이면 `@panic("zigo: argument `cp` is out of range for u21")` → 기존 패닉 브리지로 Go `NativePanicError`. 새 상태 코드 없음. 반환·out 방향은 `@intCast`(항상 안전). callback 파라미터·반환, extern struct 필드(`ZIGO012` 영역: extern struct 안의 `u21`은 C 표현이 없으므로 계속 거부, 메시지에 이유), tagged union payload, 슬라이스 원소(`[]u21`은 메모리 레이아웃이 달라 캐스트 불가 — 거부 유지) 각각의 처리를 명시한다. `abi_diff`: `bits` 21→32 변경은 signature 변경(breaking) 그대로.
- 진단: `supported()`를 `findIssue`로 흡수해 `ZIGO018 unsupported integer/float width`, `ZIGO019 unsupported type`을 낸다. `site.declaration`은 `Owner.fn`(`abi_diff.functionIdentity`와 같은 식), message에 파라미터 이름(또는 `return`)과 Zig 철자(`u21`, `f80`), hint에 대안. `semanticDocument`는 `findIssue` 뒤 단일 `error.InvalidSemantic`만 반환. `UnsupportedIrVersion`·`InvalidName`도 진단으로. `walk.zig`의 comptime 메시지는 함수 경로와 파라미터 이름을 포함하도록 문자열을 보강한다.
