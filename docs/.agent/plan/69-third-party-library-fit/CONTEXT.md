# SCOPE

- A: `walk.zig:29-61`(`.enumeration` arm), `:549-569`(암묵 enum 발견 시 `zig_path`로 등록 항목 우선 조회), `validate.zig:55-90, :218+`(모든 유도 Go 식별자 검증), `naming.zig`.
- B: `emit.zig:666-684`(shim 가드는 유지), `:2725`(승격 predicate), `:2751`, `:4184-4197`, `:431-437`(C catch), `:2869-2885`(checked 경로의 반환), `writeErrorForCode` `:4142-4162`, `lower.zig`(checked infallible 함수의 ABI 모양), `abi_diff`.
- C: `src/reflect/names.zig` `containerDocAlloc` 호출 순서.
- D: `walk.zig`(`.allocator` 파싱, 주입 파라미터 표시, `returnedOpaqueName` 완화, 생성자 pairing), `semantic.zig`(주입 파라미터 기록), `emit.zig:527-575 writeTargetCall`(주입 식 출력, 값 반환 `init`의 `create`/`destroy`), `validate.zig`(새 진단).

# CONTEXT

## Current implementation and bottlenecks

- 오늘의 패닉 동작: error union 함수는 `-2` → `errorForCode` → `NativePanicError` + poison(정상). infallible 함수는 handle 유무와 무관하게 catch가 `0`/void 반환, Go는 `nil` error. 이는 zigo가 Zig의 fatal 패닉을 "조용한 성공"으로 바꾸는 것이라 Zig 의미보다 나쁘다.
- checked 시그니처(`(T, error)`)는 `needs_handle_check`일 때만 생기고 error는 `renderHandleChecks`에서만 온다.
- `docs/limitations.md:119`는 shim이 범위검사·패닉한다고 적고 `:178-179`는 `-2` 매핑을 설명하지만 infallible 함수에 `-2`가 없다는 사실은 적지 않았다.
- enum은 시그니처를 걷다 발견될 때만 추가되고(`walk.zig:549`), struct arm(`:571-580`)은 `zig_path`로 기존 항목을 먼저 찾는 반면 enum arm은 그렇지 않다.
- 생성자 추론: `isConstructorName`/`isDestructorName`(`walk.zig:848-861`), pairing(`:112-134`). 값 반환 `init`은 생성자가 아니며 struct 반환으로 value struct가 되려다 ZIGO012/003/019로 거부된다.
- `writeTargetCall`은 `function.origin.params`를 1:1로 출력한다. "Zig에는 있고 C에는 없는 파라미터" 개념이 없다.

## Target structure and invariants

- **식별자 규칙**: reflection이 유도한 모든 Go 이름(타입, enum tag, 함수, 필드, variant)과 사용자가 준 `.name`은 `naming.isGoIdentifier`를 통과해야 하며, 실패는 `ZIGO021`로 Zig 경로(`TypeDecl.zig_path`)와 `.name` 힌트를 담는다. 예약어(`type`, `func` 등)도 거부.
- **enum 등록**: `.types` 항목에 `.repr = .enumeration`을 추가한다. `.name` 선택. 암묵 발견 시 `zig_path`로 등록 항목을 먼저 찾아 그 이름을 쓴다. 이름은 `TypeDecl.name`으로만 흐르므로 semantic.json·Go·C typedef가 자동으로 따라온다.
- **승격 정수(Go 사전검사)**: 승격된 파라미터가 하나라도 있으면 Go 공개 함수를 `(T, error)`/`error`로 승격하고, cgo 호출 **전에** `if cp > 0x1FFFFF { return ..., &RangeError{Operation, Parameter, Bits} }` 류의 검사를 한다. 새 error 타입 `RangeError`(sentinel `ErrOutOfRange`, `errors.Is`로 분류). shim 가드는 방어선으로 유지. ABI 변경 없음. 승격 규칙은 `abi.narrowInt`의 원 폭에서 읽는다.
- **패닉 가시성**: 규칙은 "Go 시그니처에 `error`가 있으면 모든 native 패닉이 그 `error`로 도달하고 handle이 poison된다. 없으면 패닉은 Zig 의미대로 fatal이다." 이를 위해 checked infallible 함수(handle 또는 승격 정수로 승격된 함수)의 C ABI를 error union 함수와 같은 모양(`int32` 상태 반환 + `out_result` 파라미터)으로 바꾼다. catch는 `-2`를 반환하고 Go checked 경로가 `errorForCode`와 `zigoPoisonAfterPanic`을 거친다. 순수 infallible 함수(handle·승격 정수 없음)는 catch에서 `abort()`한다(삼키지 않음). 둘 다 breaking이므로 다음 태그는 0.3.0. `abi_diff`는 시그니처 변경으로 자연히 breaking 보고.
- **패키지 doc 순서**: `go_package_doc` → `bindings.zig` `//!` → 루트 모듈 `//!` → 기본 문장. Ultrasync처럼 bindings 머리 주석이 Go 독자용이 아니면 그 파일을 고치는 것이 작성자 책임이며 문서에 그렇게 적는다.
- **allocator 주입**: 바인딩 옵션 `.allocator = .c_allocator | .page_allocator | .smp_allocator | "<decl path>"`(기본 없음). 설정되면 `std.mem.Allocator` 타입 파라미터는 주입 파라미터로 표시되어 C/Go 시그니처에서 빠지고 shim이 그 식을 채운다. `std.Io`는 `.io = "<decl path>"`로 같은 방식(기본 없음). 설정 없이 그런 파라미터를 만나면 `ZIGO019` 대신 "allocator source가 필요하다"는 새 진단(`ZIGO022`). 값 반환 `init`은 `.allocator`가 있을 때만 생성자로 인정하고, shim이 `const p = try alloc.create(T); p.* = try T.init(...); return p;`, 짝 `deinit`이 `p.deinit(); alloc.destroy(p)`를 한다. 주입 파라미터는 semantic.json에 `injected: true`로 남겨 abi_diff가 추가·제거를 breaking으로 보게 한다.
