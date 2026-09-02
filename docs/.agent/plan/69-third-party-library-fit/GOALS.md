# GOALS

## Problem and the end result from the user's point of view

gostty가 0.2.0으로 libghostty-vt를 바인딩하며 보고한 네 가지를 코드로 확인했다.

A. `@typeName`이 식별자가 아닌 enum(ghostty의 `lib.Enum(...)` 생성 타입, `@typeName`이 `...[0..4])`로 끝남)에서 `shortTypeName`(`src/reflect/walk.zig:777`, 마지막 `.` 뒤)이 `4])`를 만들고, 그것이 검증 없이 semantic.json → Go 타입 → C typedef로 흘러 파스 불가한 Go가 생성된다. `naming.isGoIdentifier`(`src/gen/naming.zig:201-213`)는 어디서도 호출되지 않고 `ZIGO021`(`validate.zig:57-84`)은 비어 있는지만 본다. enum은 `.types`에 등록할 수 없어(`walk.zig:29-61`, `.value`는 struct만, `.enumeration` 없음) `.name`으로 덮을 탈출구가 없다. 문서의 "등록 enum"(`docs/bindings.md:382, :531`)은 등록 수단이 없는 현 상태와 맞지 않는다.

B. 승격 정수의 shim 범위검사(`writeNarrowIntegerGuards` `emit.zig:666-684`)가 `@panic`하면 C 래퍼의 catch(`emit.zig:431-437`)가 error union이 아닌 함수에서 `return 0`/`return;`으로 조용히 zero value를 돌려준다. 더 넓게: handle을 받아 `(T, error)`로 승격된 infallible 함수(`needs_handle_check` `emit.zig:2725`, `writeCheckedFunctionReturnType` `:4184-4197`)도 `errorForCode`/`-2` 경로가 error union 함수에만 있어(`:2871+`) 항상 `nil`을 반환하고, `zigoPoisonAfterPanic`에도 닿지 않는다. 즉 **error union이 아닌 모든 함수에서 패닉이 삼켜지고 handle이 poison되지 않는다.** 공개 패키지에 `LastErrorMessage()`(`emit.zig:1117, :1843`)는 있으나 호출자가 상관관계를 알 수 없다.

C. 0.2.0의 패키지 doc fallback(루트 모듈 `//!`)은 남의 라이브러리를 바인딩할 때 Zig 사용자를 향한 글이 Go doc이 되게 한다. 바인딩 작성자가 소유한 `bindings.zig`의 `//!`가 루트보다 먼저여야 한다.

D. `std.mem.Allocator`/`std.Io`를 받고 값으로 반환하는 `init`은 C 표현이 없어 facade가 필수다. 생성자는 이름으로 추론되며(`walk.zig:848-861`) `*T`/`!*T` 반환만 생성자로 본다(`returnedOpaqueName` `:840-847`). Allocator 특수 처리는 없다. 우선순위 낮음.

작업 후: 유효하지 않은 Go 식별자는 생성 전에 진단으로 거부되고, enum을 `.types`에 `.name`과 함께 등록할 수 있다. 승격 정수 파라미터가 있는 함수는 Go에서 호출 전에 범위를 검사해 `error`로 돌려준다. Go 시그니처에 `error`가 있는 모든 함수는 native 패닉을 `NativePanicError`로 받고 handle을 poison한다. 패키지 doc은 옵션 → `bindings.zig` `//!` → 루트 모듈 `//!` → 기본 문장 순이다. `.allocator` 옵션으로 Allocator/Io 파라미터를 shim이 채우고 값 반환 `init`을 caller-owned pointer로 올린다.

## Measurable goals

- `@typeName`이 식별자가 아닌 enum fixture가 `ZIGO021`로 거부되고 메시지에 Zig 타입 경로와 `.name` 힌트가 있다. 같은 fixture를 `.types`에 `.repr = .enumeration, .name = "CursorStyle"`로 등록하면 Go `CursorStyle`, C `zg_cursor_style`, semantic.json `CursorStyle`로 생성된다.
- `u21` 파라미터를 가진 infallible 함수의 Go 시그니처에 `error`가 있고, 범위 밖 값이 cgo 호출 없이 Go에서 `error`로 돌아오며 `LastErrorMessage`가 비어 있다.
- handle을 받는 infallible 함수에서 native 패닉이 `ErrNativePanic`으로 돌아오고 handle이 poison된다는 Go 테스트.
- 패키지 doc 순서 테스트(옵션, bindings `//!`, 루트 `//!`, 기본 문장 각각).
- `Terminal.init(std.Io, Allocator, Options) !Terminal` 모양의 fixture가 `.allocator` 옵션으로 facade 없이 `New…`/`Close`를 생성한다.

## Supported scope and non-goals

지원: `src/reflect/walk.zig`, `src/gen/{validate,naming,emit,lower,abi_diff}.zig`, `src/gen/ir/semantic.zig`, 골든·예제, 문서.
비목표: error union도 handle도 승격 정수도 없는 순수 infallible 함수의 패닉 전달(이 함수들은 Zig 의미대로 fatal로 두고 문서화). 패닉 메시지 ABI 자체의 변경(계획 68 phase 4의 판단 유지). `Allocator`가 아닌 임의 타입의 주입.

## Reference source / commit / license

- gostty 보고와 facade: `/Users/ironpark/Projects/Personal/open-source/gostty/src/root.zig`(A는 :20-48, D는 :14, :51-71), `gostty/go/internal/raw/panic_probe_test.go`.
- 계획 67(승격 정수, ZIGO018-021), 68(패키지 doc 소스). 저장소 내부 작업.

## Completion criteria for the whole plan

- 측정 목표 테스트 통과. `zig build test --summary all`, `zig fmt --check build.zig src tests examples`, 예제 10개 cgo·purego 4개 `go-check`·`abi-check`·`go vet`·`go test`.
- gostty에서 facade의 A·D 부분을 제거하고 직접 바인딩해 빌드·테스트가 통과함을 확인(gostty 커밋은 사용자).
- `docs/bindings.md`(enum 등록, `.allocator`, 패키지 doc 순서, "등록 enum" 표현 정정), `docs/limitations.md`(패닉 규칙: Go 시그니처에 `error`가 있으면 모든 패닉이 도달, 없으면 fatal), `docs/generated-code.md`, `docs/configuration.md`, `CHANGELOG.md` Unreleased 절 갱신.
