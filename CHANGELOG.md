# Changelog

형식은 [Keep a Changelog](https://keepachangelog.com/ko/1.1.0/)를 따르고, 버전은
[Semantic Versioning](https://semver.org/lang/ko/)을 따릅니다. 0.x 동안은 minor 버전이
생성물의 C ABI 또는 `semantic.json` 계약이 바뀌는 릴리스를 뜻합니다.

## [Unreleased]

### Breaking

- 공개 Go 시그니처에 `error`가 있는 모든 함수의 C ABI가 상태 코드 반환 + `out_result`
  파라미터로 통일됐습니다. 이전에는 error union을 반환하는 함수만 그랬고, handle이나 승격
  정수 때문에 `error`가 붙은 함수는 C 래퍼의 패닉 착지점에 돌려줄 상태가 없어 zero value를
  반환했습니다 — 즉 fatal한 Zig 패닉이 조용한 성공이 됐고 handle도 poison되지 않았습니다.
  이제 그런 함수의 패닉은 `*NativePanicError`로 돌아오고 handle을 poison합니다. C 헤더와
  raw Go 계층의 시그니처가 바뀌므로 직접 링크하는 코드는 재생성이 필요합니다. (계획 69)
- `error`를 반환하지 않는 순수 함수의 패닉은 이제 메시지를 stderr에 적고 `abort()`합니다.
  이전에는 zero value를 반환했습니다. (계획 69)
- 승격된 정수 파라미터(`u21`, `i24` 등)를 받는 함수의 공개 Go 시그니처가 `error`를 하나 더
  반환합니다. 범위 검사가 shim이 아니라 cgo 호출 이전의 Go에서 일어나므로, 범위 밖 인자는
  native를 부르지 않고 `*RangeError`(`errors.Is(err, ErrOutOfRange)`)로 돌아옵니다. C ABI는
  바뀌지 않습니다. (계획 69)

### Added

- slice·문자열 optional(`?[]T`, `?[]const u8`, `?[:0]const u8`)을 매개변수, 반환값,
  error union payload 자리에서 지원합니다. presence 플래그를 더하지 않고 slice 자신의
  포인터가 부재를 나릅니다(`ptr == NULL`), 그래서 부재와 길이 0인 존재하는 slice가
  구별됩니다. Go에서는 매개변수가 `*[]T`/`*string`, 반환이 `([]T, bool)`/`(string, bool)`
  입니다. 반환은 기존 슬라이스 반환의 소유권 규칙(`.release` 포함)을 그대로 따릅니다.
  cgo와 purego 모두 지원합니다. `.out` slice를 optional로 만들거나, slice의 slice와
  `extern struct` slice를 optional로 만드는 것은 거부합니다. (계획 71)
- scalar·bool·enum·`extern struct` optional(`?T`)을 매개변수, 반환값, error union
  payload 자리에서 지원합니다. 이전에는 선언된 opaque type의 pointer(`?*T`)만 가능했고
  나머지는 reflection 단계의 컴파일 오류였습니다. 매개변수는 nullable pointer
  하나(`const T *`, NULL = 부재)로, 반환은 presence `bool` 반환 + `T *out_result`로,
  `E!?T`는 상태 코드 + `bool *out_result_has` + `T *out_result`로 내려갑니다. Go에서는
  매개변수가 `*T`(nil = 부재), 반환이 `(T, bool)` 또는 `(T, bool, error)`가 되므로 부재와
  "값이 0인 present"가 구별됩니다. cgo와 purego 모두 지원하며, 새 kind가 늘어난 것이라
  기존 바인딩의 ABI는 그대로입니다. `extern struct`의 field, callback signature, slice
  원소(`[]?T`), optional의 optional은 `ZIGO019`로 거부합니다. `abi-check`는 `T`와 `?T`
  사이의 변경을 breaking으로 봅니다. (계획 71)
- `*std.Io.Writer`/`*std.Io.Reader` 파라미터를 지원합니다. Go에서는 `io.Writer`/`io.Reader`가
  되고, shim이 만든 어댑터가 staging 버퍼(기본 65536, `param_meta.<name>.buffer`로 조정,
  4096..16777216)를 채울 때만 Go로 건너갑니다 — 총 `N` 바이트 출력의 `Write` 호출은
  `ceil(N / 버퍼)`회를 넘지 않습니다. Go `Write`/`Read`의 error는 `*StreamError`(`Unwrap`으로
  원 error, `errors.Is` 가능)로 돌아오고 native 상태 코드보다 우선하며, Go panic은 기존
  `*CallbackPanicError` 경로로 재전파되고, `nil` 스트림은 `ErrNilStream`으로 거부됩니다.
  cgo와 purego 모두 지원하며, 새 kind가 늘어난 것이라 기존 바인딩의 ABI는 그대로입니다.
  파라미터 자리 밖(반환, 필드, 콜백 시그니처, 슬라이스 원소, optional)과
  `.retention = .retained`는 `ZIGO023`으로 거부합니다. (계획 70)
- 생성될 Go 이름이 생성 전에 검사됩니다. 등록된 타입 이름, 필드·enum tag 이름, 함수 이름 중
  Go 식별자가 될 수 없는 것이 있으면 `ZIGO021`이 Zig 타입 경로와 함께 거부합니다. 이전에는
  `@typeName`이 `...[0..4])`로 끝나는 comptime 생성 타입의 이름이 그대로 `.go` 파일에 실려
  gofmt에서야 터졌습니다. (계획 69)
- `.allocator`가 설정되어 있으면 값으로 반환하는 `init`(`T`/`!T`)도 생성자로 인정됩니다.
  shim이 `create`/`init`/실패 시 `destroy`를 하고, 짝 `deinit` 래퍼가 `deinit` 뒤에
  `destroy`까지 합니다. Go에서는 다른 handle과 같은 `New…`/`Close` 쌍입니다. (계획 69)
- 바인딩의 `.allocator`와 `.io`로 `std.mem.Allocator`, `std.Io` 파라미터를 주입할 수
  있습니다. 그 파라미터는 C와 Go 시그니처에서 빠지고 shim이 지정한 식을 넘깁니다. 설정
  없이 만나면 `ZIGO022`로 거부합니다. (계획 69)
- `.types`에 `.repr = .enumeration`으로 enum을 등록하고 `.name`으로 Go/C 이름을 지정할 수
  있습니다. `@typeName`이 이름이 아닌 comptime 생성 enum(ghostty의 `lib.Enum(...)`)을 facade
  없이 바인딩할 수 있습니다. 이미 등록된 enum은 signature가 닿을 때 Zig 경로로 조회되므로
  이름이 한 번만 정해집니다. (계획 69)
- 승격된 정수 파라미터를 가진 바인딩의 errors 파일에 `ErrOutOfRange` sentinel과 `RangeError`
  타입이 생성됩니다. `Operation`, `Parameter`, `Type`으로 어떤 인자가 어떤 Zig 폭을 넘겼는지
  알 수 있습니다. (계획 69)

### Changed

- 패키지 doc은 `go_package_doc` → `bindings.zig`의 `//!` → 라이브러리 루트 모듈의 `//!` →
  기본 문장 순으로 정해집니다. 남이 쓴 라이브러리를 바인딩할 때 Zig 사용자를 향해 쓰인 루트
  주석이 Go 패키지 doc이 되지 않도록, 바인딩 작성자가 소유한 파일이 먼저입니다. (계획 69)

## [0.2.0] - 2026-09-02

### Breaking

- `.written = .return`인 out 슬라이스 파라미터는 C 시그니처에서 `_written` out 파라미터를
  더 이상 갖지 않습니다. 쓴 개수는 함수의 반환값 하나로만 전달됩니다. `abi-check`는
  `.all`과 `.return` 사이의 변경을 breaking으로 보고합니다. (계획 68)
- `u21`, `i24` 같은 2의 거듭제곱이 아닌 정수 폭이 C 경계에서 다음 2의 거듭제곱으로
  승격됩니다(`u21` → `uint32_t`, Go `uint32`). 이전에는 거부됐으므로 기존 바인딩의 ABI는
  바뀌지 않지만, `semantic.json`의 `bits`는 원래 폭을 유지하고 폭 변경은 breaking입니다.
  (계획 67)

### Added

- 바인딩 경로가 임의 깊이의 네임스페이스 struct를 따라갑니다. `root.unicode.codepointWidth`
  같은 경로가 동작하며, 네임스페이스는 C 심볼(`zg_unicode_codepoint_width`), raw Go 이름,
  `semantic.json` identity(`unicode.codepointWidth`)에 반영됩니다. 공개 Go 이름은 마지막
  세그먼트만 씁니다. `.discover = .recursive`로 중첩 컨테이너 발견을 켤 수 있고, 기본값
  `.public`은 그대로 1단계입니다. (계획 67)
- 지원되지 않는 타입이 위치 있는 진단으로 보고됩니다. `ZIGO018`(정수·실수 폭),
  `ZIGO019`(타입), `ZIGO020`(IR 버전), `ZIGO021`(이름)이 함수, 파라미터, Zig 타입 철자를
  담아 출력되며 스택 트레이스 대신 진단만 나옵니다. reflection 단계의 `@compileError`도
  함수 경로와 파라미터 이름을 포함합니다. (계획 67)
- 범위를 벗어난 승격 정수 인자는 shim이 검사해 기존 패닉 브리지를 통해 Go
  `NativePanicError`로 돌아옵니다. extern struct 필드, 슬라이스 원소, callback 시그니처의
  비 2의 거듭제곱 폭은 이유를 담은 `ZIGO018`로 계속 거부됩니다. (계획 67)
- `LockOSThread` 비용 벤치마크가 07-event-queue에 추가됐고 결과가 `docs/limitations.md`에
  기록됐습니다. 가벼운 error union 호출에서 약 2%라 패닉 메시지 ABI는 바꾸지 않았습니다.
  (계획 68)

### Changed

- 패키지 doc의 fallback 소스가 `bindings.zig`의 `//!`에서 라이브러리 루트 모듈의 `//!`로
  바뀌었습니다. 순서는 `go_package_doc` 옵션, 루트 모듈 `//!`, 기본 문장입니다. (계획 68)
- handle을 획득하는 호출 경로에서 잉여 `defer runtime.KeepAlive`가 제거됐습니다.
  `defer x.zigoRelease()`가 이미 handle을 함수 끝까지 붙잡습니다. `Close`와 Go 메모리를 C에
  넘기는 경우의 `KeepAlive`는 유지됩니다. (계획 68)
- Go 타입 이름이 선언 폭이 아닌 승격 폭으로 표기됩니다. (계획 67)

## [0.1.0] - 2026-09-02

첫 태그 릴리스입니다. 이 릴리스까지의 주요 내용은 다음과 같습니다.

### Handle 모델

- handle은 잠금 대신 호출 수를 셉니다. `Close`는 표시만 하고 마지막으로 나가는 호출이
  자원을 해제하므로 어떤 호출자도 다른 호출자를 기다리지 않습니다.
- Zig 패닉이 통과한 handle은 poison되어 이후 호출이 `NativePanicError`로 거부되며,
  native 자원은 해제하지 않고 남깁니다.
- 런타임 심볼에 접두어가 붙어 두 바인딩이 한 바이너리를 공유할 수 있습니다.

### 슬라이스와 extern struct

- out 슬라이스 파라미터에 `.written = .return` 힌트가 추가됐습니다. native가 반환한
  개수만 채워지고 그 뒤 원소는 호출 전 값 그대로입니다.
- bool 필드가 없는 extern struct 슬라이스는 cgo에서도 캐스트 한 번으로 넘어가고, Go 쪽
  컴파일 시점 레이아웃 가드가 그 근거를 고정합니다. 반환 경로도 raw 계층이 소유한 할당을
  재해석해 두 번째 복사를 하지 않습니다.
- 에러 유니온 슬라이스 payload, 호출자 소유 슬라이스 반환과 해제 함수, 문자열 슬라이스
  파라미터, sentinel C 문자열을 지원합니다.

### 메타데이터와 문서

- `semantic.json`의 `symbol`이 실제 export 심볼과 일치합니다. `abi-check`는 옛 규칙에서
  새 규칙으로의 1회 정정을 compatible로 봅니다.
- 생성된 Go doc이 식별자로 시작하지 않는 문장을 두 줄 형식으로 내고, `//` 그룹 주석과
  빈 줄 없이 이어진 선언의 doc 공유를 지원합니다. 모든 생성 패키지에 패키지 doc이 있습니다.

[0.2.0]: https://github.com/ironpark/zigo/compare/0.1.0...0.2.0
[0.1.0]: https://github.com/ironpark/zigo/releases/tag/0.1.0
