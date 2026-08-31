# 공유 라이브러리와 purego 백엔드

zigo는 두 가지 Go 백엔드를 생성한다. 기본값 `.cgo`는 정적 링크와 cgo 호출을 사용하고,
opt-in `.purego`는 네이티브 공유 라이브러리를 런타임에 로드해 `CGO_ENABLED=0`으로 빌드한
Go 프로그램에서 호출한다. 공개 Go API는 두 백엔드에서 동일하며, 달라지는 것은 raw
구현 파일과 로더 API뿐이다.

| 항목 | `.cgo` (기본) | `.purego` |
|---|---|---|
| `link_mode` | `.static` 또는 `.dynamic` | `.dynamic`만 |
| Go 빌드 요구사항 | C 컴파일러, `CGO_ENABLED=1` | 없음, `CGO_ENABLED=0` 가능 |
| 네이티브 아티팩트 | 빌드 시 링크 | 실행 시 로드 |
| 배포 단위 | Go 바이너리 하나 | Go 바이너리 + 플랫폼별 공유 라이브러리 |
| 추가 Go 의존성 | 없음 | `github.com/ebitengine/purego v0.10.2` |
| 지원 범위 | 네이티브 macOS/Linux | 네이티브 macOS/Linux amd64·arm64 |

## 빌드 설정

```zig
const purego_bindings = zigo.addGoBindings(b, .{
    .name = "mylib",
    .module = mylib,
    .bindings = b.path("src/bindings.zig"),
    .go_dir = b.path("go-purego"),
    .go_module = "example.com/mylib/go-purego",
    .target = target,
    .optimize = optimize,
    .backend = .purego,
    .link_mode = .dynamic,
});
_ = purego_bindings.addStandardSteps(b, .{ .name_prefix = "purego" });
```

`.backend = .purego`는 `.link_mode = .dynamic`을 요구하며, 지원하지 않는 조합이나 타깃은
빌드 그래프를 만드는 시점에 실패한다. 한 저장소에서 두 백엔드를 모두 제공하려면 위처럼
`go_dir`과 `go_module`이 다른 바인딩 세트를 각각 등록하고 `name_prefix`로 스텝 이름을
분리한다. `examples/04-callback`, `examples/07-event-queue`,
`examples/08-telemetry-hub`가 이 구성을 사용한다.

## 재현 절차

```bash
# 1. 공유 라이브러리와 Go 소스를 생성하고 zig-out/lib에 설치한다.
zig build purego-go

# 2. 백엔드 전제, 모듈 핀, 설치된 아티팩트를 한 번에 검증한다.
zig build purego-go-verify

# 3. C 컴파일러 없이 테스트한다.
cd go-purego && CGO_ENABLED=0 go test ./...
```

> 한 빌드에 두 백엔드를 등록하면 두 아티팩트가 같은 `zig-out`에 설치되지만 이름이
> 겹치지 않는다. 정적 바인딩은 `lib<name>_zigo.a`를 경로로 직접 링크하고, purego
> 헤더는 `zigo_<name>_purego.h`로 설치된다. 따라서 순서에 상관없이 두 백엔드를 한
> 트리에서 생성하고 테스트할 수 있다. 아티팩트를 다른 위치에 설치했다면 테스트에는
> `ZIGO_LIBRARY_PATH`로 실제 경로를 알려준다.

`purego-go-verify`는 생성물 최신 상태(`go-check`), 네이티브 라이브러리 설치(`go-lib`),
`go-doctor`, 그리고 `abi_base`가 설정된 경우 `abi-check`까지 의존한다. purego 백엔드의
`go-doctor`는 cgo 대신 다음을 검사한다.

- 호스트 플랫폼이 지원 대상(macOS/Linux, amd64/arm64)인지
- `go.mod`가 검증된 purego 버전을 요구하는지
- 설치된 공유 라이브러리가 존재하고 플랫폼 로더로 실제 로드되는지

```
PASS purego: no C compiler required at Go build time
PASS purego platform: macos/aarch64 is supported
PASS purego module: github.com/ebitengine/purego v0.10.2
PASS shared library: /…/zig-out/lib/libmylib_zigo.dylib loads at run time
```

실패는 실행할 명령을 함께 알려준다. 예를 들어 아티팩트가 없으면
`run \`zig build go-lib\``, 모듈 요구사항이 없으면
`run \`go get github.com/ebitengine/purego@v0.10.2\``를 출력하고 종료 코드 1로 끝난다.

## 라이브러리 로딩

생성된 공개 패키지는 로더 API를 함께 노출한다.

```go
// 명시 경로가 가장 우선한다.
if err := mylib.LoadLibrary("/opt/myapp/lib/" + mylib.DefaultLibraryName); err != nil {
    return err
}
if !mylib.LibraryLoaded() {
    return errors.New("bindings are not ready")
}
```

`LoadLibrary(path)`의 경로 결정 순서는 다음과 같다. 후보는 [로딩 정책](#로딩-정책-설정)으로
바꿀 수 있다.

1. 인자로 받은 경로
2. 설정된 환경 변수 (기본값은 `ZIGO_<PACKAGE>_LIBRARY_PATH`, `ZIGO_LIBRARY_PATH`)
3. 설정된 search path
4. `DefaultLibraryName` (플랫폼 기본 파일명; 플랫폼 로더의 검색 경로에서 찾는다)

로딩은 원자적이다. 필요한 심볼을 모두 해석한 뒤에만 호출 표면을 공개하므로, 실패한
로드는 부분적으로 호출 가능한 패키지를 남기지 않고 다른 경로로 재시도할 수 있다.
실패는 경로·심볼·원인을 담은 `*LibraryError`로 반환되며 플랫폼 로더 오류를 `Unwrap`으로
노출한다. 로드에 성공한 핸들은 프로세스 수명 동안 닫지 않는다. 생성된 함수 포인터와
살아 있는 네이티브 핸들 때문에 안전한 unload가 불가능하기 때문이다. 로드 전에 바인딩을
호출하면 같은 진단 메시지로 panic한다.

`DefaultLibraryName`은 생성 시점이 아니라 실행 시점에 `runtime.GOOS`로 결정된다. 따라서
커밋된 생성물은 macOS와 Linux에서 동일하며, 생성물 최신 상태 검사도 두 플랫폼에서 같은
결과를 낸다.

## 로딩 정책 설정

`library_loading`으로 라이브러리를 어디서 어떤 순서로 찾을지, 첫 호출에 자동으로 로드할지,
로더를 공개 API로 노출할지를 선언한다. 기본값은 위에서 설명한 동작 그대로다.

```zig
.library_loading = .{
    // 환경 변수 다음에 이 순서로 시도한다. 파일이 아니면 디렉터리로 보고
    // 플랫폼 라이브러리 이름을 붙인다.
    .search_paths = &.{ "${EXECUTABLE_DIR}", "${EXECUTABLE_DIR}/../lib", "/opt/myapp/lib" },
    // 첫 바인딩 호출에서 위 후보를 한 번 시도한다.
    .automatic = true,
    // 공개 패키지에서 LoadLibrary/LibraryLoaded/DefaultLibraryName을 감춘다.
    .exported_api = false,
    // 기본값은 패키지 전용 이름과 공용 이름 두 개다.
    .env_vars = &.{ "MYAPP_LIBRARY_PATH" },
},
```

| 필드 | 기본값 | 설명 |
|---|---|---|
| `search_paths` | 없음 | 환경 변수 다음에 순서대로 시도할 위치 |
| `env_vars` | `null` | `null`은 `ZIGO_<PACKAGE>_LIBRARY_PATH`와 `ZIGO_LIBRARY_PATH`. 빈 목록은 환경 변수를 보지 않음 |
| `automatic` | `false` | 첫 바인딩 호출에서 자동 로드 |
| `exported_api` | `true` | 공개 패키지에 로더 API를 노출 |

`library_loading`은 `.backend = .purego`에서만 쓸 수 있고, `exported_api = false`는
`automatic = true`와 공개 패키지와 분리된 raw 패키지를 요구한다. 잘못된 조합은 빌드
그래프를 만드는 시점에 실패한다.

### 후보 순서

1. `LoadLibrary(path)`에 넘긴 경로 (비어 있지 않으면 이것만 시도한다)
2. `env_vars`의 각 환경 변수 중 값이 있는 것
3. `search_paths`의 각 항목
4. `DefaultLibraryName` (플랫폼 로더 검색 경로)

`search_paths` 항목이 플랫폼 라이브러리 확장자로 끝나면 파일 경로로 그대로 쓰고, 그렇지
않으면 디렉터리로 보고 `DefaultLibraryName`을 붙인다. `${EXECUTABLE_DIR}`는 실행 중인
실행 파일의 디렉터리로 확장되며, 확인할 수 없으면 그 항목은 건너뛴다. 항목에 `:`는 쓸 수
없다. 생성기로 전달할 때 목록 구분자이기 때문이다.

후보를 여러 개 시도해 모두 실패하면 하나의 `*LibraryError`가 모든 시도를 묶어 반환된다.
후보가 하나뿐이면 그 시도의 경로와 심볼이 그대로 보존된다.

### 자동 로딩

`.automatic = true`이면 첫 바인딩 호출이 후보 목록을 **한 번** 시도한다. 성공하면 이후
호출은 그대로 진행되고, 모두 실패하면 모든 후보를 담은 오류로 panic한다. 공개 API가 오류를
반환하지 않는 형태이므로 panic 외에 다른 선택지가 없다. 실패 후에도 `LoadLibrary`가 노출된
구성이라면 다른 경로로 명시적 재시도를 할 수 있다.

`examples/08-telemetry-hub`의 purego 바인딩이 이 구성을 사용한다. 테스트는 로더를 전혀
호출하지 않고, 공개 패키지에는 바인딩된 API만 있다.

### 환경 변수 이름

기본 환경 변수는 패키지 전용 이름(`ZIGO_TELEMETRY_HUB_LIBRARY_PATH`)이 먼저이고 공용
`ZIGO_LIBRARY_PATH`가 그다음이다. 한 프로세스가 zigo purego 패키지를 둘 이상 로드할 때
공용 변수 하나로 서로의 라이브러리를 가리키지 않도록 하기 위한 것이다. 배포에서 환경 변수를
아예 쓰지 않으려면 `.env_vars = &.{}`로 비운다.

`go-report`가 적용된 정책을 출력한다.

```text
library loading: automatic on first call, loader API internal
library environment: ZIGO_TELEMETRY_HUB_LIBRARY_PATH,ZIGO_LIBRARY_PATH
library search paths: ${EXECUTABLE_DIR}:${EXECUTABLE_DIR}/../lib:../../zig-out/lib
```

## 패키징과 배포

- 공유 라이브러리는 타깃별 아티팩트다. 파일명은 macOS `lib<name>_zigo.dylib`,
  Linux `lib<name>_zigo.so`이며 `zig build go-lib`이 `zig-out/lib`에 설치한다.
- 배포 대상 OS·아키텍처 조합마다 해당 호스트에서 빌드한다. purego는 Go 애플리케이션
  빌드에서 C 컴파일러를 제거할 뿐, 하나의 Zig 아티팩트를 여러 타깃에 이식해 주지 않는다.
  zigo의 reflector가 빌드 중 실행되므로 크로스 컴파일도 지원하지 않는다.
- 아티팩트에는 Zig 캐시 경로가 새겨지지 않는다. 런타임 의존성은 바인딩한 Zig 모듈의
  의존성과 생성된 panic 경계가 사용하는 플랫폼 C 런타임뿐이다.
- 애플리케이션은 배포 레이아웃에 맞는 절대 경로를 `LoadLibrary`에 넘기거나, 플랫폼
  로더 검색 경로(`@rpath`, `LD_LIBRARY_PATH`, 시스템 라이브러리 디렉터리)를 직접
  구성해야 한다. zigo는 생성된 Go 코드에 빌드 머신 경로를 커밋하지 않는다.
- 커밋 대상은 생성된 Go 소스와 `zigo/` 메타데이터다. 공유 라이브러리는 릴리스
  아티팩트로 배포한다.

### 보안 주의사항

- `LoadLibrary`는 임의의 네이티브 코드를 프로세스에 로드한다. 경로는 애플리케이션이
  통제하는 위치여야 하며, 쓰기 가능한 공용 디렉터리나 사용자 입력에서 온 경로를 그대로
  넘기지 않는다.
- 자동 로딩은 이 결정을 빌드 시점의 정책으로 옮긴다. `search_paths`에는 배포에서 쓰기
  권한이 통제되는 위치만 넣고, 상대 경로는 실행 시점의 작업 디렉터리에 따라 달라지므로
  배포용으로는 `${EXECUTABLE_DIR}` 기준 경로나 절대 경로를 쓴다.
- 환경 변수는 후보 중 가장 먼저 시도된다. 신뢰 경계가 중요한 배포에서는
  `.env_vars = &.{}`로 비워 외부에서 로드 대상을 바꿀 수 없게 한다.
- `ZIGO_LIBRARY_PATH`와 파일명 fallback은 편의 기능이다. 신뢰 경계가 중요한 배포에서는
  절대 경로를 명시하고, 필요하면 로드 전에 서명이나 체크섬을 검증한다.
- 로드된 라이브러리는 언로드되지 않으므로, 잘못된 아티팩트를 로드한 프로세스는 재시작해야
  한다.

## 콜백

purego 백엔드는 콜백 파라미터를 C 함수 포인터와 `uintptr_t` userdata로 낮추고, 콜백을
받는 네이티브 진입점에 `_purego_v1` 접미사를 붙인다. cgo 백엔드의 심볼과 트램폴린은
그대로 유지되므로 기존 cgo ABI는 바뀌지 않는다.

- 고유한 콜백 시그니처마다 영구 dispatcher를 하나 만든다. `purego.NewCallback` 슬롯은
  회수할 수 없으므로 콜백 값마다 네이티브 콜백을 만들지 않는다.
- 콜백 값은 동기화된 정수 토큰 레지스트리에 저장한다. borrowed 토큰은 호출이 끝나면,
  retained 토큰은 `Close`나 자동 cleanup에서 삭제된다. 삭제는 진행 중인 호출을 기다린다.
- 콜백에서 발생한 panic은 부호 있는 32비트 결과를 가진 콜백 ABI에서 `-3`으로, 이미
  해제된 토큰 호출은 `-4`로 결정적으로 변환된다.

## 알려진 제약

- purego는 v1 이전 베타 소프트웨어다. zigo는 `v0.10.2`를 고정해 생성·검증하고, 사용은
  생성된 raw 파일에만 격리한다. 다른 버전을 요구하는 `go.mod`는 `go-doctor`가 경고한다.
- 초기 지원 범위는 네이티브 macOS/Linux amd64·arm64다. Windows, 모바일, purego Tier 2
  타깃은 후속 작업이다.
- 정적 링크는 cgo 전용이다.
- Go race detector는 여전히 cgo를 요구하므로 `CGO_ENABLED=0` 테스트에서는 사용할 수 없다.
  race 커버리지는 cgo 백엔드 테스트에서 확보한다.
- zigo가 `go.mod`를 새로 만들 때만 purego 요구사항을 기록한다. 이미 있는 모듈은 직접
  `go get github.com/ebitengine/purego@v0.10.2`를 실행한다.

## CI

공유 라이브러리는 타깃별 아티팩트이므로 지원하는 OS·아키텍처마다 잡이 필요하다. 이
저장소의 `purego` 잡은 `ubuntu-latest`, `ubuntu-24.04-arm`, `macos-latest`,
`macos-15-intel`에서 다음을 실행한다.

```bash
zig build purego-go purego-go-verify          # 생성, 전제 검사, 아티팩트 로드 확인
git status --porcelain -- examples            # 생성물이 플랫폼 간에 동일한지 확인
tests/inspect_shared_library.sh <library> <symbol>…
zig build shared-library-smoke -- <library> <symbol>…
CGO_ENABLED=0 go test ./...
```

`tests/inspect_shared_library.sh`는 플랫폼 파일명, 빌드 캐시 경로가 새겨지지 않았는지,
요청한 심볼이 export되었는지, 그리고 해석되지 않은 `zg_` 심볼이 없는지를 검사한다.
마지막 검사는 cgo 트램폴린 의존성이 남았는지를 잡아내며, 그런 라이브러리는
`CGO_ENABLED=0` 프로세스에서 사용할 수 없다. `shared-library-smoke`는 같은 검사를 실제
플랫폼 로더로 수행한다.

아티팩트 계약의 세부 사항은 [공유 라이브러리 계약](shared-library.md)에 있다.
