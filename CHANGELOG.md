# Changelog

형식은 [Keep a Changelog](https://keepachangelog.com/ko/1.1.0/)를 따르고, 버전은
[Semantic Versioning](https://semver.org/lang/ko/)을 따릅니다. 0.x 동안은 minor 버전이
생성물의 C ABI 또는 `semantic.json` 계약이 바뀌는 릴리스를 뜻합니다.

## [Unreleased]

### Added

- `addGoBindings`의 `targets`로 한 cgo 바인딩 세트가 여러 `GOOS`/`GOARCH`용 네이티브
  라이브러리를 빌드합니다. Go 소스는 한 번 생성되고, raw 패키지는 타깃마다
  `#cgo <goos>,<goarch> LDFLAGS:` 줄을 가지며 각 라이브러리와 정적 링크 입력은
  `library_dir/<goos>_<goarch>/`에 설치됩니다. 생성기는 반복 가능한
  `--cgo-target <goos>/<goarch>` 플래그를 받습니다. 목록을 비워 두면 기존 배치와 생성물이
  그대로 유지됩니다.
- `cgo_flags.target_ldflags`로 한 플랫폼에만 붙는 링크 플래그를 지정합니다. 항목마다
  `#cgo <goos>[,<goarch>] LDFLAGS:` 줄이 따로 생성되며, 생성기는 반복 가능한
  `--target-ldflags <goos>[,<goarch>]=<flags>` 플래그를 받습니다.
- `.cgo_dynamic` 실행 시 공유 라이브러리를 찾지 못하는 원인과 rpath·환경 변수 해결 방법을
  설정 문서에 추가했습니다.
- `.repr = .enumeration` 등록 항목의 `.text = true`로 Go enum에 `Parse<Enum>`,
  `MarshalText`, `UnmarshalText`를 생성합니다. open enum은 `String()`이 돌려주는
  `<Enum>(N)` 철자도 파싱합니다. 알 수 없는 문자열은 패키지 공용 `EnumParseError`로
  보고하며, enum이 아닌 항목의 opt-in은 `ZIGO051`입니다. `abi-check`는 인코딩 제거를
  breaking으로 판정합니다.
- 함수 메타 `.iterator = .{ .name = "All" }`로 `?T`·`!?T`를 반환하는 메서드에
  range-over-func wrapper를 생성합니다. Go 시그니처에 `error`가 있으면
  `iter.Seq2[T, error]`, 없으면 `iter.Seq[T]`이며 `.cancel` 메서드는 wrapper도 `ctx`를
  받습니다. 잘못된 형태는 `ZIGO050`, 이름 충돌은 `ZIGO024`이고 `abi-check`는 wrapper
  제거·이름 변경을 breaking으로 판정합니다.
- `.link = .purego`도 `targets`를 받습니다. 나열한 플랫폼의 공유 라이브러리가
  `library_dir/<goos>_<goarch>/`에 설치되고, 생성된 로더는 검색 경로의 디렉터리마다
  실행 중인 `GOOS_GOARCH` 하위 디렉터리를 찾습니다. 생성기와 `report`는
  `--library-platform-dirs` 플래그를 받고, doctor는 호스트에서 실행 가능한 타깃의
  라이브러리를 검사합니다.

### Changed

- 외부 도구 실행 결과와 doctor 표시 로직을 분리하고, 스트림·Materialized의 생성 및
  레이아웃 결정 코드를 책임별 모듈로 정리했습니다. 공개 API와 생성물은 변경하지 않습니다.
- 소유권 판정과 Go 핸들 수명 관리 코드 생성을 전용 모듈로 분리했습니다.
  공개 API와 생성물은 변경하지 않습니다.
- 스트림·디코더·핸들 종료 경합의 cgo·purego 회귀 테스트를 공통 계약 테스트 모듈로 통합했습니다.

### Fixed

- `go-doctor`가 `CC="zig cc"`의 `cc` 인자를 버려 정상 컴파일러를 사용 불가로 판정하던
  0.9.1 회귀를 수정했습니다. 따옴표로 감싼 경로와 컴파일러 옵션을 보존하고,
  실행 실패와 버전 조회의 비정상 종료를 구분합니다.

## [0.9.1] - 2026-09-05

### Added

- 최소 바인딩을 직접 실행할 수 있는 `00-quick-start` 예제와 stdin/stdout 스트림 복사 CLI를
  추가했습니다. Go 실행 예제와 대용량·오류·메모리 경계 회귀 테스트도 보강했습니다.

### Changed

- 사용자 가이드와 예제 README를 작업 순서 중심으로 재구성하고, 현재 구현과 설명을 맞췄습니다.
- CI에 콜백·핸들·스트림의 Go race 검사를 추가했습니다.

### Fixed

- Go reader의 일시적인 `(0, nil)`을 EOF로 오인하던 문제와 데이터와 함께 반환된 오류가
  유실되던 문제를 수정했습니다. cgo·purego가 같은 읽기 처리를 사용하며, 연속 100회
  진행이 없으면 `io.ErrNoProgress`를 반환합니다.
- Materialized 반환값 직렬화 중 할당 실패가 발생하면 부분 버퍼를 정리합니다.
  Go 디코더는 배열 범위와 개수를 메모리 할당 전에 검사합니다.
- `go-doctor`는 C 컴파일러의 버전 조회가 실패한 경우 사용 가능으로 보고하지 않습니다.
  위 런타임 수정을 적용하려면 Go 바인딩을 재생성하고 native 라이브러리를 다시 빌드해야 합니다.
- Go reader·writer를 Zig `streamRemaining`으로 연결할 때 writer staging 버퍼가 차면
  멈추던 문제를 수정했습니다. 빈 `drain` 요청도 기존 버퍼를 비워 진행하며, cgo·purego에
  동일하게 적용됩니다. 기존 사용자는 새 zigo로 native 라이브러리를 다시 빌드해야 합니다.

## [0.9.0] - 2026-09-05

`semantic.json`에 `interfaces` 필드가 추가되어 minor 릴리스입니다. 인터페이스를 등록하지 않은
바인딩의 `semantic.json`과 생성물은 그대로입니다.

### Added

- `.interfaces` 등록. 등록한 opaque handle 집합이 같은 Go 시그니처로 제공하는 메서드 집합에
  이름을 붙여 `<package>_interfaces_gen.go`에 Go 인터페이스와 `var _ Iface = (*T)(nil)` 단언을
  냅니다. 구조 검사와 렌더링한 시그니처 비교는 `ZIGO049`, 이름 충돌은 `ZIGO024`로 보고하고,
  `abi-diff`는 인터페이스 추가를 호환, 제거와 메서드·타입·`io.Closer` 변경을 breaking으로
  봅니다. `examples/05-pipeline`의 `Batch`가 예제입니다.

### Changed

- 생성기 내부 구조를 정리했습니다. `src/gen/emit.zig`는 출력 파일별 `src/gen/emit/`으로,
  `src/gen/validate.zig`는 순서가 곧 우선순위인 규칙 표와 관심사별 `src/gen/validate/`로
  나뉘었고, `build.zig`는 소비자 API만 남기고 저장소 테스트 배선을 `build/`로 옮겼습니다.
  `Must` 변형 여부와 콜백 Go error 도달 여부는 `lower`가 한 번 정해 `AbiFn`에 기록하고,
  공개 패키지 helper는 렌더링한 본문에서 참조를 읽어 냅니다. 생성물은 바이트 단위로 같습니다.
- `go-coverage`가 root module과 bindings 파일이 함께 import하는 소스를 한 번만 읽고 파싱합니다.
- 반환값과 파라미터의 소유권을 `lower`가 함수마다 하나의 레코드(`abi.Ownership`,
  `abi.ParamOwnership`)로 기록하고, cgo·purego의 복사 후 release 경로, owned handle 결과,
  ZIGO015/016/048의 release 후보 판정이 그 레코드와 규칙 함수 하나를 읽습니다. 생성물과
  `semantic.json`은 그대로입니다.

### Fixed

- `errors.lock.json` 직렬화 중 메모리 부족이 `WriteFailed`로 보고되던 문제를 고쳤습니다.
- 다른 함수에서 `.go_error = true`로 표시한 콜백 시그니처를 쓰는 함수도 `Must` 변형을 얻으므로,
  ZIGO024 충돌 검사가 그 이름까지 확인합니다.

## [0.8.1] - 2026-09-03

### Fixed

- 등록 조상이 없는 dependency module 타입을 `.name`과 다른 Go 이름으로 등록하면 shim이
  `target.<name>`만 적어 root가 그 이름을 내보내지 않으면 컴파일에 실패하던 문제를 고쳤습니다.
  이제 shim이 module 아래 경로, Zig 타입 이름, 등록 이름 순으로 root가 내보내는 첫 선언을
  comptime에 고르고, 어느 것도 없으면 후보를 나열한 컴파일 에러를 냅니다. `.materialized`,
  `.opaque`, `.value` 모두 같은 규칙을 씁니다.
- `go-coverage`가 pub 선언이 많은 root module에서 `evaluation exceeded 1000 backwards branches`로
  실패하던 문제를 고쳤습니다. comptime 순회 함수마다 branch quota를 올립니다.
- `go-coverage`의 미등록 타입 목록이 root 아래 선언 경로(`Terminal.Options`)를 씁니다. 이전에는
  마지막 이름만 적어 같은 이름의 타입을 구분할 수 없었고, generic instantiation과 익명 컨테이너는
  mangled `@typeName`(`Limits__union_39951`)으로 나왔습니다. 이제 root가 선언한 경로로 적고,
  선언 경로가 없는 타입의 이유 문구는 `Limits.(anonymous union)`처럼 읽을 수 있게 풉니다.

## [0.8.0] - 2026-09-03

### Added

- `.repr = .materialized` struct 결과를 versioned caller-owned buffer 하나로 직렬화합니다.
  반환값, error union, batch slice, written out buffer를 cgo와 purego에서 idiomatic Go
  struct와 `string`, slice, pointer 트리로 해독하며 release 호출 한 번으로 수명을 끝냅니다.
- `.cancel.canceled`로 취소를 뜻하는 Zig error 이름을 지정할 수 있습니다. 생략하면 기존
  `Canceled`를 사용하며, 예를 들어 `Cancelled`를 지정하면 Go가 `ErrCancelled`를
  `ctx.Err()`로 변환합니다.
- callback 타입이나 함수의 callback 파라미터에
  `.on_callback_failure = .{ .result = N }`을 선언해 panic, 삭제된 token, Go error 때 native로
  돌려줄 도메인 값을 고를 수 있습니다. 실패 기록과 rethrow는 유지되며 semantic JSON,
  `ZIGO046` 범위 검증, ABI-compatible diff, cgo/purego dispatcher에 반영됩니다.
- `.cancel` 함수가 Go callback도 받으면 callback panic, 삭제된 token, Go error가 callback
  state에 연결된 취소 플래그를 순차 일관 store로 올립니다. native loop가 callback의 in-band
  실패 반환값을 무시해도 다음 폴링 지점에서 멈추며 cgo와 purego가 같은 동작을 합니다.
- `addGoBindings`의 `.go_must_variants = true` 옵션으로 오류를 반환하는 공개 함수와
  메서드에 `Must<Name>` 동반 API를 생성할 수 있습니다. 생성자는 `MustNew<Type>`을 쓰고
  `Close`는 제외하며, 실패 시 checked API의 typed error를 그대로 panic합니다.
- `[]const u21` 같은 비정규 폭 정수 slice를 승격된 Go 원소 타입(`[]uint32`)으로 노출합니다.
  입력과 out buffer는 바인딩 allocator로 만든 임시 slice에서 원소별 변환하고, caller-owned
  반환은 Go 복사 전에 승격합니다. 범위 검사는 scalar 승격과 같은 `RangeError`를 사용하며,
  allocator가 없으면 설정 힌트가 있는 `ZIGO045`를 보고합니다.
- `.repr = .opaque`로 등록한 struct의 by-value receiver와 파라미터를 지원합니다. Go와 C는
  기존 handle pointer를 전달하고 shim이 Zig 호출 시 값을 복사하므로, receiver lifecycle
  검사와 일반 `*T` 파라미터 API를 유지하면서 wrapper 없이 값 시그니처를 바인딩할 수 있습니다.
- 정수 backing의 `packed struct`를 `.repr = .value`로 등록할 수 있습니다. bool, 정수,
  등록 enum, 중첩 packed value 필드를 Go mirror와 `Backing`/`FromBacking`으로 노출하고,
  scalar가 가능한 함수·optional·error payload·extern struct·flatten·field accessor·callback
  자리에서는 backing 정수 하나로 전달합니다. 지원하지 않는 필드는 `ZIGO044`입니다.
- 함수 메타데이터에 `.covers = "Type.name"` 또는 경로 목록을 추가했습니다. `go-coverage`는
  해당 상류 선언을 wrapper를 통한 bound로 세고 `wrapped` 항목과 wrapper 경로를 보고하며,
  `semantic.json`에도 문서 전용 `covers` 목록을 기록합니다.
- `std.atomic.Value(T)`를 bool, 정수, 부동소수, 등록 enum의 값 자리에서 평범한 `T`로
  노출합니다. field accessor는 순차 일관 load/store를 사용하고, flatten·값 struct·값 union·
  값 파라미터와 반환은 원시 값을 복사합니다. atomic field가 있는 struct slice는 항상
  원소별 복사 경로를 사용합니다.
- `*std.atomic.Value(u32|i32|u64|i64)` 파라미터를 호출 동안 공유하는 Go
  `*atomic.Uint32|Int32|Uint64|Int64`로 노출합니다. purego는 주소를 명시적으로 pin하며,
  retained 주소와 지원하지 않는 atomic 폭은 `ZIGO043`으로 거부합니다.

### Changed

- `.use_pkg_config = .force` system library는 cgo 지시자를 만들기 전에 `pkg-config --exists`로
  원래 이름과 `lib` 접두사 이름을 차례로 확인하고, 실제로 해석되는 package 이름을 내보냅니다.
- Go 생성기는 public wrapper가 실제로 참조하는 struct 변환, bool 변환, optional handle,
  callback 진단 helper만 내보냅니다. 생성된 package의 공개 API는 유지하면서 `staticcheck`
  `U1000`이 보고하던 사용되지 않는 내부 helper를 제거합니다.
- `abi-diff`가 packed value struct의 변경을 분류합니다. backing 폭 안에서 필드를 뒤에 덧붙이는 것은
  호환 변경이고, 필드 순서 변경·폭 변경·제거·이름 변경은 breaking입니다.

### Fixed

- `.constructs` 함수의 명시적 `.name`을 무시하고 항상 `New<Type>` Go wrapper를 생성하던
  문제를 고쳤습니다. 이름을 지정하지 않은 생성자의 기존 이름은 그대로 유지됩니다.
- 대상 module이 import하는 module의 system library, library path, framework, pkg-config 정보가
  생성된 cgo 지시자에서 빠지던 문제를 고쳤습니다. 전체 import 그래프를 의존 먼저 순서로
  수집하고 중복 항목은 한 번만 내보냅니다.
- `go-check`가 `zigo/semantic.json`과 `zigo/errors.lock.json`도 비교합니다. 이전에는 생성된 Go 파일만
  확인해서 stale한 sidecar 파일이 로컬에서는 통과하고 CI의 재생성 diff에서만 잡혔습니다.
- `go-coverage`의 미등록 타입 목록이 generic instantiation 이름을 괄호 안에서 잘라 표시하고,
  translate-c 익명 struct나 flatten으로 문서에 등록된 value struct를 미등록으로 보고하던 문제를
  고쳤습니다.
- `go-coverage`의 unbound 이유가 첫 번째 문제만 보고하고 stream writer/reader를 metadata 누락으로
  잘못 분류하던 문제를 고쳤습니다. 이제 모든 문제 parameter와 return을 이름으로 나열하고 plain
  struct 안의 첫 번째 미등록 field도 함께 표시합니다.

## [0.7.4] - 2026-09-03

### Fixed

- shim의 등록 타입 spelling이 `root.` 경로에만 적용되던 문제를 고쳤습니다. dependency module의
  타입(`terminal.Terminal.Options`)은 경로가 접두사로 겹치는 가장 가까운 등록 조상
  (`Terminal`)을 거쳐 `target.Terminal.Options`로 적으므로, 상류 타입을 root에 다시 내보내지
  않아도 컴파일됩니다. 등록 조상이 없는 타입은 이전처럼 root가 내보내는 이름을 씁니다.

## [0.7.3] - 2026-09-03

### Fixed

- `zigo-gen abi-diff`가 잘못된 `semantic.json`(선언 없는 타입 참조 등)에 `unreachable` panic을
  내던 문제를 고쳤습니다. 두 입력을 먼저 검증해 파일 이름을 적은 ZIGO 진단을 출력하고 종료
  코드 1로 끝납니다.
- 검증이 tagged union의 `tag_type` enum 참조와 flatten된 field 타입의 해석을 확인하지 않아
  하류에서 panic할 수 있던 틈을 `ZIGO010`으로 막았습니다.
- 골든 생성 케이스의 테스트 스텝이 `semantic.json`이나 `expected/` 파일을 바꿔도 캐시된 결과를
  재사용하던 문제를 고쳤습니다. `addDirectoryArg`는 경로만 해시하므로 케이스의 파일을 모두
  스텝 입력으로 등록합니다.

## [0.7.2] - 2026-09-03

### Fixed

- shim이 등록 타입을 항상 root 기준 `target.<이름>`으로 적던 문제를 고쳤습니다. 이제 reflection이
  기록한 `zig_path`를 따라 `target.Terminal.Options`처럼 선언한 container를 거쳐 적으므로,
  `Terminal.init(options: Terminal.Options)`를 `.flatten`으로 바인딩할 때 root에 같은 이름을
  다시 내보낼 필요가 없습니다. flatten literal, 값 유니온 재구성, boxed 생성자, 시그니처의
  handle·value struct 타입에 같은 규칙이 적용됩니다.

## [0.7.1] - 2026-09-03

### Fixed

- `param_meta.<파라미터>.flatten`이 struct 전체를 reflection하던 문제를 고쳤습니다. 이제 선택한
  field만 걷고 나머지는 Zig default 유무만 확인하므로, `?DynamicRGB`처럼 C로 표현할 수 없는
  member가 섞인 options struct도 바인딩됩니다. flatten된 plain struct의 선언은 선택한 field만
  담으며, `abi-diff`는 auto-layout struct 선언의 field 목록을 비교하지 않습니다.
- 0.7.0 태그의 CI를 Linux에서 깨뜨린 abi-diff 단위 테스트 픽스처(스택을 벗어난 포인터)를
  고쳤습니다. 0.7.0은 GitHub 릴리스가 만들어지지 않았으므로 이 버전을 사용하십시오.

## [0.7.0] - 2026-09-03

### Changed

- `ZIGO009`, `ZIGO021`, `ZIGO024`, `ZIGO036` 진단에 충돌하거나 수명 계약이 빠진 선언에서
  바로 적용할 수 있는 이름 또는 release 함수 제안을 `note:`로 추가했습니다.
- Windows 공유 라이브러리(DLL)와 import library가 Zig 기본값인 `bin` 대신 `install.library_dir`
  (기본 `lib`)에 설치됩니다. 다른 플랫폼과 같은 디렉터리에서 로더 기본 경로와 `#cgo` 플래그를
  계산하기 위한 변경이며, `zig-out/bin/<name>_zigo.dll`을 직접 참조하던 스크립트는
  `zig-out/lib/`로 옮겨야 합니다.
- `zigo-gen report`가 다른 handle의 메서드인 생성자를 `(*Parent).NewChild`로 표시합니다.
  이전에는 receiver가 있으면 생성자로 인식하지 못했습니다.
- `abi-diff`가 두 `semantic.json`을 실제로 lowering한 C 시그니처로 비교합니다. lowering이
  버리는 정수 폭·의미 힌트 같은 Go 표면은 semantic 문서로 계속 비교하며, 값 유니온 variant
  추가처럼 C 시그니처가 실제로 늘어나는 변경은 `signature changed` 항목을 함께 보고합니다.

### Added

- `addGoBindings`에 라이브러리·헤더의 설치 디렉터리와 파일명을 정하는 `install` 옵션을
  추가했습니다. cgo 플래그와 정적 링크 입력, purego 기본 로딩 경로,
  `GoBindings.library_path` 및 표준 빌드 스텝이 같은 배치를 사용합니다.
- callback `param_meta`에 문서 전용 `.reentrancy = .allowed | .forbidden`과
  `.thread = .caller | .any` 계약을 추가했습니다. 선택한 계약은 `semantic.json`과 cgo·purego
  양쪽의 callback type 및 함수 Go doc에 기록되며 runtime thread pinning은 바꾸지 않습니다.
- root와 등록 타입의 공개 함수를 bound, excluded, unbound로 분류하는 `go-coverage` build
  step을 추가했습니다. 기존 signature 제약에 따른 unbound 이유, 함수가 참조하는 미등록 공개
  타입, `.fields` accessor를 포함한 비율을 text로 출력하고 `coverage_json` 옵션으로 JSON
  artifact도 기록할 수 있습니다.
- `.packages`의 `types`와 `namespaces`에 trailing `*` prefix pattern을 추가하고, 선택된
  함수·타입에서 signature, union payload, callback, lifecycle target, field accessor를 따라
  등록 타입을 함께 배정하는 `.closure = true`를 추가했습니다. 빈 pattern은 `ZIGO041`, 두
  closure package의 모호한 소유권은 양쪽 package를 적는 `ZIGO042`로 진단합니다.
- `param_meta.<파라미터>.flatten`으로 plain Zig options struct의 bool·정수·실수·등록 enum
  field와 그 optional을 개별 Go/C 인자로 펼칠 수 있습니다. shim은 선택한 field만 struct
  literal에 적어 나머지 Zig default를 보존하며, default 없는 미선택 field는 `ZIGO040`으로
  진단합니다. cgo와 purego, boxed value `init`, `abi-diff`에 동일하게 반영됩니다.
- by-value tagged union에 integer-backed `packed struct` payload와 재귀적인 scalar
  `extern struct` payload를 지원합니다. `.omit_variants`로 교차할 수 없는 variant를
  C/Go surface에서 제외할 수 있고, 같은 snapshot layout을 쓰는 값 반환도 cgo와 purego에서
  지원합니다. 반환값의 active tag가 제외된 variant이면 typed `OmittedVariant` error를
  반환합니다.
- 자유 함수 메타데이터의 `.receiver`와 `.receiver`/`.strip_prefix`/`.functions` group을
  추가했습니다. 등록 opaque pointer를 첫 비주입 파라미터로 받는 자유 함수를 cgo와 purego의
  method로 붙이고, group의 공통 Zig 접두사를 기본 Go 이름에서 제거할 수 있습니다. 잘못된
  receiver 또는 접두사는 `ZIGO038`로 진단합니다.
- opaque 타입 등록의 `.fields` 메타데이터로 bool·정수·실수·등록 enum 필드의 getter와 선택적
  setter를 생성합니다. dotted path는 struct 값과 non-optional single pointer를 통과할 수
  있으며 cgo와 purego, ABI 검사에 동일하게 반영됩니다. 잘못된 경로와 지원하지 않는 타입은
  `ZIGO037`로 진단합니다.

## [0.6.3] - 2026-09-03

### Added

- `void`를 반환하는 Zig callback을 cgo와 purego에서 지원합니다. 생성된 C/Zig trampoline과
  Go callback 타입도 반환값 없이 생성되며, purego dispatcher의 내부 반환값은 native에서
  무시됩니다.

### Fixed

- 기존 handle의 method로 retained callback을 다시 등록할 때 이전 `cgo.Handle` 또는 purego
  callback token이 남던 누수를 고쳤습니다. callback은 함수·파라미터별 slot에 교체되고,
  이전 등록은 성공한 native 호출 뒤 해제되며, 남은 모든 slot은 `Close`와 자동 cleanup에서
  해제됩니다. `.packages`의 공유 lifecycle에서도 같은 규칙을 사용합니다.

## [0.6.2] - 2026-09-03

### Fixed

- 공용 lifecycle 렌더러의 단위 테스트가 초기화되지 않은 program을 읽어 Linux에서 죽던 문제를
  고쳤습니다. 생성물 변화는 없으며, 0.6.1 태그는 이 테스트 때문에 CI와 릴리스가 실패해 GitHub
  릴리스가 만들어지지 않았습니다.

## [0.6.1] - 2026-09-03

### Fixed

- borrowed view를 receiver로 삼는 `.child_of_receiver = true` constructor가 view와 실제
  owning handle의 카운터를 섞던 문제를 고쳤습니다. 이제 임의 깊이의 borrowed view를
  통과해도 자식 예약과 해제가 같은 owning handle에 적용됩니다.
- 등록 타입의 C typedef, 함수·projection·snapshot 심볼, enum 상수가 같은 C 식별자로
  정규화되면 깨진 헤더를 생성하는 대신 `ZIGO036`으로 두 선언을 함께 진단합니다.
- `.returns = .caller`와 `.release`를 `?[]T`, `!?[]T`, `?[:0]const u8`,
  `!?[:0]const u8` 반환에도 적용합니다. 부재·오류 경로에서는 release하지 않고, 존재하는
  값만 Go 메모리로 복사한 뒤 release합니다.
- `.packages`로 나눈 공개 패키지의 enum·struct·runtime 파일이 쓰지 않는 패키지 import를 붙여
  import 순환(`import cycle not allowed`)을 만들던 문제를 고쳤습니다. 타입 이름을 부분 문자열로
  찾던 판정을 버리고, 본문을 먼저 한정한 뒤 실제로 쓰인 `zigo_pkg_*`/`zigo_default` 선택자만
  import합니다.

## [0.6.0] - 2026-09-03

### Added

- receiver 메서드의 `.returns = .borrowed`로 등록 opaque pointer를 부모 수명에 묶인 일반 Go
  handle로 반환할 수 있습니다. cgo와 purego 모두 부모 Close 무효화, active-call 경합 방지,
  poison 전파, optional `(*T, bool, error)`를 지원하며 명시·오용은 semantic metadata와
  `ZIGO033`–`ZIGO035` 진단으로 구분합니다.
- `bindings.zig`의 `.packages`로 등록 타입, namespace, 함수를 기본 공개 Go 패키지 아래의
  하위 패키지로 나눌 수 있습니다. 패키지 간 타입은 import path와 한정 이름으로 생성되며,
  순환은 `ZIGO032`로 거부합니다. cgo와 purego는 `internal/lifecycle`의 handle·error 계약을
  공유하고 각 공개 패키지에서 기존 error type과 sentinel 이름을 다시 제공합니다.
- `semantic.json`에 opt-in `packages`와 선언별 `package` 필드를 추가했습니다. 기본 패키지
  배정은 필드를 생략해 기존 단일 패키지 문서를 유지하고, `abi-diff`는 패키지 이동을 breaking
  Go surface 변경으로 보고합니다.

### Fixed

- `.cgo_static`의 정적 링크 입력을 module이 import하는 module에서도 수집합니다. 라이브러리가
  자기 C/C++ 의존성을 자신의 module에 붙이고 바인딩이 그 module을 import하는 경우(ghostty-vt의
  simdutf, highway)에도 archive가 cgo 링크 줄에 들어갑니다.
- `go-lib`와 기본 `install`이 라이브러리와 함께 헤더도 설치합니다. 이전에는 `go` 스텝만 헤더를
  설치해, 새 체크아웃에서 `zig build go-lib` 직후의 `go test`가 헤더를 찾지 못했습니다.

## [0.5.0] - 2026-09-03

### Added

- receiver constructor의 `.child_of_receiver = true` 메타를 추가했습니다. 생성된 자식 handle은
  부모를 참조하고 열린 자식 수를 등록하며, 부모 `Close`는 자식이 남아 있으면
  `ErrHandleInUse`를 감싼 `*HandleInUseError`를 반환합니다. 자식을 닫은 뒤 부모를 다시 닫을
  수 있고, 부모의 poison 상태는 자식 호출에도 전파됩니다. cgo와 purego가 같은 수명 규칙을
  사용하며 `semantic.json`에는 opt-in한 constructor에만 필드가 기록됩니다.
- payload가 모두 void, scalar, 또는 등록 enum인 tagged union을 함수 매개변수 값으로
  전달할 수 있습니다. cgo와 purego 모두 variant constructor와 `Tag()`를 제공하고,
  C ABI는 tag와 variant별 payload slot으로 결정적으로 평탄화합니다.

### Fixed

- 같은 잘린 `@typeName`을 가진 서로 다른 comptime 생성 enum이 첫 번째 등록 타입 하나로
  합쳐지던 문제를 고쳤습니다. 등록 타입을 comptime identity로 연결하고 충돌하는
  `semantic.json`의 `zig_path`에는 등록 이름을 붙여 구분합니다.
- 숫자로 시작하는 enum tag를 단독 Go 식별자로 검사해 거부하던 문제를 고쳤습니다. 이제
  `80_cols`는 실제 생성되는 전체 상수 이름(`DeccolmMode80Cols`)으로 검증합니다.

## [0.4.2] - 2026-09-03

### Fixed

- 호스트 reflection module이 `linkLibrary`로 붙인 정적 라이브러리의 설치 헤더와
  libc/libc++ 설정을 잃던 0.4.0 회귀를 고쳤습니다. 정적 라이브러리의 호스트 변형을 복제해
  연결하므로, 호출자 C/C++ 소스가 해당 라이브러리를 통해 libc++를 쓰는 경우에도 네이티브와
  크로스 `go-lib` 생성이 동작합니다.

## [0.4.1] - 2026-09-03

### Fixed

- `.cgo_static`의 정적 링크 입력(0.4.0)이 Windows와 크로스 컴파일에서 깨지던 문제를 고쳤습니다.
  archive를 Zig cache의 절대 경로 대신 `zig-out/lib/lib<name>.a`로 설치해 `${SRCDIR}` 상대
  경로로 적으므로 cgo가 Windows 경로와 `.lib`를 거부하지 않고, reflector는 module을 호스트용으로
  복제해 실행하므로 대상 전용 archive를 링크하려다 실패하지 않습니다.

## [0.4.0] - 2026-09-03

### Added

- `go_package_path` 옵션을 추가했습니다. 공개 Go 패키지 이름과 생성 경로를 분리하며,
  `"."`을 지정하면 `go_dir`의 모듈 루트에 생성되어 `<go_module>` 자체로 import할 수
  있습니다. 같은 경로의 `raw_package`는 계속 colocate됩니다.
- `.types`의 enum 등록에 `.exhaustive = false` opt-in을 추가했습니다. Zig non-exhaustive enum을
  cgo와 purego에서 이름 붙은 상수 밖의 값까지 그대로 왕복하며, 생성된 Go `String()`은
  미지의 값을 `Type(N)`으로 표시합니다. opt-in이 없으면 기존 `ZIGO002`가 유지되고,
  exhaustive enum에 잘못 붙이면 `ZIGO029`입니다.
- 다른 handle의 메서드인 생성자를 지원합니다. 예를 들어 allocator가 주입되는
  `fn newStream(gpa, terminal: *Terminal) !*Stream`은
  `func (t *Terminal) NewStream() (*Stream, error)`가 되고, 반환된 `Stream`은 자신의
  destructor와 짝지어진 caller-owned handle입니다.
- `cgo_flags.extra_ldflags`를 추가했습니다. 기본 또는 override LDFLAGS 뒤, module의 system
  library 앞에 추가됩니다.
- `.cgo_static`이 module의 `.other_step` 정적 라이브러리와 `.static_path` archive를 절대
  경로로 최종 cgo 링크에 전달하고, install step도 그 artifact에 의존합니다. cache 경로는
  commit하지 않는 별도 Go 파일에만 기록되어 `go-check`는 플랫폼 간 결정성을 유지합니다.

### Fixed

- method receiver의 한 글자 이름이 같은 함수의 파라미터와 겹쳐(`Terminal.setTitle(t)` 등)
  컴파일되지 않던 문제를 고쳤습니다. receiver 타입 snake_case 이름의 가장 짧은 비충돌
  접두사를 쓰고 모든 함수 emit 경로가 같은 이름을 공유합니다.
- handle·승격 정수 범위·optional handle 파라미터 검사가 실패할 때 optional 반환의 presence
  값이 빠져 Go 반환값 개수가 부족하던 문제를 고쳤습니다. 직접 optional과 error union 안의
  optional 모두 이제 `zero, false, err`를 반환합니다.
- `addStandardSteps`가 네이티브 바인딩 라이브러리를 기본 `install` 스텝에도 연결합니다.
  plain `zig build` 뒤에 `zig-out/lib`를 바로 사용할 수 있으며,
  `.install_library_by_default = false`로 이 연결을 끌 수 있습니다.

## [0.3.3] - 2026-09-02

### Fixed

- 주입 파라미터(`std.mem.Allocator`, `std.Io`)가 handle보다 앞에 선언된 함수
  (`fn freeTerminal(gpa: Allocator, self: *Terminal) void`)도 메서드와 `.destroys` 대상으로
  인식합니다. receiver 판정이 주입 파라미터를 건너뛰고, shim은 `self`를 Zig가 선언한
  자리에 넣어 호출합니다. `semantic.json`은 이 경우에만 `receiver_at`을 적습니다.

## [0.3.2] - 2026-09-02

### Added

- 함수 메타 `.constructs = "<Type>"` / `.destroys = "<Type>"`. 타입 밖에 자유 함수로
  선언된 생성자와 소멸자를 이름 규칙과 무관하게 짝지어 Go의 생성자와 `Close()`로
  내보냅니다. 메타가 없으면 기존 이름 규칙이 그대로 fallback으로 남습니다.

### Fixed

- 타입 밖에 선언된 함수가 생성자·소멸자로 짝지어지거나 handle 파라미터로 메서드가 될 때,
  shim이 선언되지도 않은 `target.<Type>.<name>` 경로를 부르던 문제를 고쳤습니다. Go의
  소속(`go_owner`)과 Zig 호출 경로(`zig_path`)가 `semantic.json`에서 분리되었고, `.name`으로
  이름을 바꾼 함수도 원래 선언을 부릅니다.
- `.params`가 주입 파라미터(`std.mem.Allocator`, `std.Io`)를 세지 않습니다. 이름을 Go에
  보이는 파라미터만 적으면 되고, 개수가 맞지 않으면 zigo 내부의 comptime 인덱스 오류가
  아니라 `ZIGO027` 진단이 나옵니다.
- `.release`가 가리키는 함수가 allocator를 받아도 됩니다. 주입 파라미터를 뺀 시그니처로
  판정하고 shim이 호출할 때 채우므로, 더 이상 `ZIGO016`으로 거부되지 않습니다.
- `abi-diff`가 주입 파라미터를 시그니처 비교에서 제외합니다. allocator를 파라미터로
  받도록 바꾸는 것은 C 시그니처를 움직이지 않으므로 breaking이 아니며, 대신 `go_owner`가
  바뀌면 breaking으로 보고합니다.

## [0.3.1] - 2026-09-02

### Fixed

- `semantic.json`의 `source.path`가 생성기를 호출한 디렉터리에 따라 달라지던 문제를
  고쳤습니다. 이제 `bindings.zig`가 있는 디렉터리 기준 상대 경로를 `/` 구분자로 기록하므로
  같은 소스는 어디서, 어느 OS에서 생성해도 같은 바이트가 나옵니다. 0.3.0으로 생성한
  `semantic.json`은 재생성해야 `go-check`가 통과합니다.

## [0.3.0] - 2026-09-02

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

- 함수 메타 `.cancel = .{ .param = "..." }`로 긴 native 호출을 Go `context.Context`로 끊을 수
  있습니다. 지정한 파라미터(타입은 `*const std.atomic.Value(u32)`)는 Go 시그니처에서 사라지고
  `ctx context.Context`가 첫 인자가 됩니다. 호출마다 Go가 플래그 워드를 하나 만들고
  `ctx.Done()`을 감시하는 goroutine이 그것을 세우며(호출이 끝나면 정리), Zig가
  `error.Canceled`를 돌려주고 ctx가 실제로 취소됐으면 `ctx.Err()`가 반환됩니다. 폴링은 원자적
  load 하나라 경계를 넘지 않습니다. 취소는 협조적이라 대상 함수가 플래그를 읽어야 합니다.
  `.cancel`이 없는 함수의 생성물은 바이트 그대로입니다. (계획 72)

- Zig 메서드가 스트림을 **내주는** 방향을 지원합니다. `fn writer(self) *std.Io.Writer`는
  handle에 `Write([]byte) (int, error)`와 `Flush() error`를, `fn reader(self) *std.Io.Reader`는
  `Read([]byte) (int, error)`(끝은 `io.EOF`)를 생성하므로 `io.Copy`가 양방향으로 그대로
  동작합니다. 포인터는 Go로 건너가지 않고 shim이 매 호출마다 접근자를 다시 부르므로 보관된
  스트림이 상할 일이 없고, 수명은 receiver handle의 기존 획득·해제·poison 규칙이 답합니다.
  스트림 반환은 파라미터 없는 메서드에서 반환 타입 그 자체여야 하며, 아니면 `ZIGO023`입니다.
  (계획 72)

- Go 콜백이 `error`를 돌려줄 수 있습니다. `param_meta.<이름>.go_error = true`를 켜면 Go 콜백
  타입이 `func(...) (i32, error)`가 되고, 콜백이 돌려준 error는 native 호출이 끝난 뒤 공개
  함수에서 `*CallbackError`(`errors.Is(err, ErrCallbackFailed)`, `Unwrap`으로 원래 error)로
  돌아옵니다. trampoline은 error를 저장하고 native 쪽에 `-5`를 돌려줍니다 — `-3`(panic),
  `-4`(삭제된 토큰)와 구별됩니다. retained 콜백의 error는 그 handle을 건드리는 다음 호출에서
  나옵니다. Zig 콜백 반환은 `i32`여야 하며 아니면 `ZIGO025`입니다. 기본값은 꺼짐이라 기존
  바인딩의 생성물은 바뀌지 않고, C ABI도 바뀌지 않습니다. (계획 72)

- `*std.Io.Reader` 파라미터에 무콜백 경로가 생겼습니다. Go `io.Reader`가 `Bytes() []byte`
  (`*bytes.Buffer`)나 `zigoBytes() []byte`(직접 정의한 타입을 위한 훅)를 가지면 남은 바이트가
  슬라이스 하나로 넘어가고, shim이 `std.Io.Reader.fixed`로 감싸므로 경계를 넘는 콜백이
  **0회**입니다. C ABI는 계획 70이 미리 잡아 둔 `(<name>_data, <name>_data_len)` 자리를 그대로
  쓰므로 바뀌지 않습니다. 이 경로에서는 소비한 바이트 수가 보고되지 않아 Go reader가
  전진하지 않습니다. 그 밖의 reader는 예전처럼 트램폴린으로 읽습니다. (계획 72)

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

[Unreleased]: https://github.com/ironpark/zigo/compare/0.9.1...HEAD
[0.9.1]: https://github.com/ironpark/zigo/compare/0.9.0...0.9.1
[0.9.0]: https://github.com/ironpark/zigo/compare/0.8.1...0.9.0
[0.8.1]: https://github.com/ironpark/zigo/compare/0.8.0...0.8.1
[0.8.0]: https://github.com/ironpark/zigo/compare/0.7.4...0.8.0
[0.7.4]: https://github.com/ironpark/zigo/compare/0.7.3...0.7.4
[0.7.3]: https://github.com/ironpark/zigo/compare/0.7.2...0.7.3
[0.7.2]: https://github.com/ironpark/zigo/compare/0.7.1...0.7.2
[0.7.1]: https://github.com/ironpark/zigo/compare/0.7.0...0.7.1
[0.7.0]: https://github.com/ironpark/zigo/compare/0.6.3...0.7.0
[0.6.3]: https://github.com/ironpark/zigo/compare/0.6.2...0.6.3
[0.6.2]: https://github.com/ironpark/zigo/compare/0.6.1...0.6.2
[0.6.1]: https://github.com/ironpark/zigo/compare/0.6.0...0.6.1
[0.6.0]: https://github.com/ironpark/zigo/compare/0.5.0...0.6.0
[0.5.0]: https://github.com/ironpark/zigo/compare/0.4.2...0.5.0
[0.4.2]: https://github.com/ironpark/zigo/compare/0.4.1...0.4.2
[0.4.1]: https://github.com/ironpark/zigo/compare/0.4.0...0.4.1
[0.4.0]: https://github.com/ironpark/zigo/compare/0.3.3...0.4.0
[0.3.3]: https://github.com/ironpark/zigo/compare/0.3.2...0.3.3
[0.3.2]: https://github.com/ironpark/zigo/compare/0.3.1...0.3.2
[0.3.1]: https://github.com/ironpark/zigo/compare/0.3.0...0.3.1
[0.3.0]: https://github.com/ironpark/zigo/compare/0.2.0...0.3.0
[0.2.0]: https://github.com/ironpark/zigo/compare/0.1.0...0.2.0
[0.1.0]: https://github.com/ironpark/zigo/releases/tag/0.1.0
