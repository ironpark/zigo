# GOALS

## Problem and the end result from the user's point of view

외부 소비자(gostty, Ultrasync)가 다음에 부딪힐 네 가지를 미리 닫는다.
1. optional은 선언된 opaque 타입의 포인터에서만 허용된다(`src/reflect/walk.zig:529-534` `@compileError`, `validate.zig:119,163`). `?u32`, `?f64`, `?bool`, `?[]const u8`, `?Enum`, `?ExternStruct`는 Zig 라이브러리에서 흔하지만 zigo는 거부한다.
2. 두 네임스페이스에 같은 이름의 함수가 있으면 공개 Go 이름이 충돌한다(계획 67의 결정: 공개 이름은 마지막 세그먼트만). `ZIGO007`(`validate.zig:277,286`)은 C 심볼만 검사해 `go build`의 중복 선언 오류로야 드러난다.
3. 모든 진단의 `Site.path`가 `"semantic.json"`으로 고정이다(`validate.zig:38,59,66` 등). `names.zig`가 `bindings.zig`와 루트 소스의 AST를 갖고 있으므로 `bindings.zig:12:5`처럼 가리킬 수 있다.
4. 릴리즈가 수동이다(0.1.0, 0.2.0 모두 `gh release create`를 손으로). README·getting-started의 `zig fetch` URL이 main을 가리켜 사용자가 breaking 변경을 그대로 받는다.

작업 후: 스칼라·enum·extern struct·슬라이스 optional이 C 경계에서 presence + 값으로 lowering되고 Go에서 `(T, bool)`/포인터로 나온다. 공개 Go 이름 충돌이 생성 시점 진단으로 잡힌다. 진단이 `bindings.zig`의 줄·열을 가리킨다. 태그를 푸시하면 CHANGELOG 절을 본문으로 GitHub 릴리즈가 생성되고, 문서의 fetch URL이 최신 태그를 가리킨다.

## Measurable goals

- `?u32` 파라미터·반환, `?[]const u8` 파라미터, `?Point`(extern struct) 파라미터·반환 fixture가 cgo·purego에서 생성되고 Go 테스트가 null과 값 왕복을 검증한다.
- 같은 공개 이름을 가진 두 함수 fixture가 새 진단 코드로 거부되고 메시지가 두 Zig 경로와 `.name` 힌트를 담는다.
- `ZIGO018`·`ZIGO021` 등 함수·파라미터 관련 진단이 `--> src/bindings.zig:LINE:COL (Owner.fn)` 형태로 출력된다는 CLI 계약 테스트.
- 태그 푸시로 릴리즈가 생성되는 워크플로가 있고, 문서의 fetch 명령이 태그를 고정한다.

## Supported scope and non-goals

지원: 파라미터·반환·out 파라미터 위치의 optional(스칼라, bool, enum, 승격 정수, extern struct, 슬라이스, 문자열), 공개 이름 충돌 진단, 진단 소스 위치, `release.yml`, 문서 fetch URL.
비목표: extern struct 필드의 optional(C 표현 없음, 계속 거부), callback 시그니처의 optional, optional 슬라이스 원소(`[]?u32`), optional의 optional, tagged union payload의 optional(별도 판단).

## Reference source / commit / license

- 계획 67(공개 이름 결정, 위치 있는 진단), 69(식별자 검증, `ZIGO022`). 저장소 내부 작업.

## Completion criteria for the whole plan

- 측정 목표 테스트 통과. `zig build test --summary all`, `zig fmt --check build.zig src tests examples`, 예제 10개 cgo·purego 4개 통과.
- `docs/bindings.md`(optional 표, 이름 충돌), `docs/limitations.md`, `docs/generated-code.md`(optional ABI), `docs/development.md`(릴리즈 절차), `CHANGELOG.md` Unreleased 갱신.
