# GOALS

## Problem and the end result from the user's point of view

`../gostty`가 libghostty-vt를 zigo로 소비하다 세 제약을 만났고, 모두 코드로 확인됐다(`gostty/docs/zigo-findings.md`).
1. 바인딩 경로가 2단계로 고정이다. `pathOwner`(`src/reflect/walk.zig:293-304`)가 마지막 `.`으로만 나누고, 소유자는 `.root` 또는 등록된 `.types`에서만 찾는다(`pathContainer` `:306-314`, `containerHasPath` `:316-343`은 1단계 decl만 본다). libghostty-vt는 루트에 `pub fn`이 없고 `unicode`, `osc`, `kitty`, `color` 같은 네임스페이스 struct로 API를 묶으므로 `root.unicode.codepointWidth`가 거부되고(`walk.zig:255-262`), gostty는 `src/root.zig`에 손으로 평탄화 facade를 써야 했다.
2. `u21` 파라미터가 `error.UnsupportedIntegerWidth`로 거부된다(`integerSupported` `src/gen/validate.zig:438-441`, `supported` `:641`). 코드포인트를 `u21`로 쓰는 것은 Zig 관용구라 ghostty 전반에 깔려 있다.
3. 생성기 오류에 위치가 없다. `supported()`는 ZIGO 진단 체계 밖에서 bare `error.UnsupportedIntegerWidth`를 반환해(`validate.zig:6-15`, `:641-649`) 어느 함수·파라미터인지 알 수 없다.

작업 후: `path`를 `.`으로 분할해 임의 깊이의 네임스페이스 struct를 따라가고, `u21` 같은 폭은 C/Go 경계에서 다음 2의 거듭제곱으로 승격되며 shim이 범위를 검사하고, 지원되지 않는 타입은 함수·파라미터·Zig 타입명을 담은 ZIGO 진단으로 보고된다. gostty는 facade 없이 ghostty-vt 모듈을 직접 소비할 수 있다.

## Measurable goals

- `root.unicode.codepointWidth`, `root.a.b.c.fn` 형태의 경로가 fixture에서 통과하고, 심볼 `zg_unicode_codepoint_width`, Go 함수 `UnicodeCodepointWidth`, `semantic.json` identity `unicode.codepointWidth`, doc·파라미터 이름 수집이 모두 동작한다.
- `u21` 파라미터·반환이 헤더 `uint32_t`, Go `uint32`로 나가고 shim이 범위를 검사한다. `semantic.json`의 `bits`는 21 그대로다.
- 지원되지 않는 폭·타입이 `ZIGO018`/`ZIGO019` 진단으로 `Owner.fn`과 파라미터 이름, Zig 타입 철자를 담아 출력되고 bare error·스택 트레이스가 사라진다.

## Supported scope and non-goals

지원: `src/reflect/{walk,names}.zig`, `src/gen/{validate,lower,emit,naming,diagnostic}.zig`, 골든·예제, 문서.
비목표: `.discover`의 재귀 기본값 변경(옵트인만 추가), `Site.path`를 `bindings.zig` 소스 줄로 매핑하는 일(후속), 새 ABI 상태 코드 도입, 임의 정수 폭의 Go 타입 신설.

## Reference source / commit / license

- `/Users/ironpark/Projects/Personal/open-source/gostty/docs/zigo-findings.md`, `gostty/src/root.zig`(facade), `gostty/src/bindings.zig`. 저장소 내부 작업, 외부 코드 없음.
- 선례: `abi_diff.zig:207-224`의 `legacyFunctionSymbolAlloc` 1회 이행 허용(계획 65).

## Completion criteria for the whole plan

- 측정 목표 테스트가 모두 통과한다. `zig build test --summary all`, 예제 10개 cgo·purego 4개 `go-check`·`abi-check`·`go vet`·`go test`, `zig fmt --check build.zig src tests examples`.
- gostty에서 facade를 제거하고 `.path = "root.unicode.codepointWidth"`로 직접 바인딩해 `zig build go && go test`가 통과한다(계획 밖 저장소이므로 확인만, 커밋은 사용자).
- `docs/bindings.md`, `docs/limitations.md`, `docs/generated-code.md` 갱신.
