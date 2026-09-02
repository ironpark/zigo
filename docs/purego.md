# 공유 라이브러리와 purego

zigo의 기본값 `.cgo_static`은 정적 링크와 cgo 호출을 사용합니다. 선택적인 `.purego`는
네이티브 공유 라이브러리를 runtime에 로드하므로 Go 프로그램을 `CGO_ENABLED=0`으로
빌드할 수 있습니다. 공개 Go API는 두 backend에서 동일하고 raw 구현과 loader만 달라집니다.

> Zig shared library는 배포할 OS·architecture 조합마다 하나씩 필요하지만, 한 호스트에서
> 모두 만들 수 있습니다. `zig build purego-go-lib -Dtarget=x86_64-windows`처럼
> 크로스 컴파일을 지원합니다. Go 쪽도 마찬가지입니다. 생성된 purego 패키지는 순수
> Go이므로 C 툴체인 없이 `GOOS=windows CGO_ENABLED=0 go build ./...`로 빌드할 수
> 있습니다. 단일 실행 파일이 목적이라면 기본 `.cgo_static`을 사용하세요.

| 항목 | `.cgo_static` / `.cgo_dynamic` | `.purego` |
|---|---|---|
| 링크 시점 | 빌드 | 실행 |
| Go 빌드 요구사항 | C 컴파일러, `CGO_ENABLED=1` | 없음, `CGO_ENABLED=0` 가능 |
| 네이티브 아티팩트 | 빌드 시 링크 | 실행 시 로드 |
| 배포 단위 | Go 바이너리 하나 | Go 바이너리 + 플랫폼별 공유 라이브러리 |
| 추가 Go 의존성 | 없음 | `github.com/ebitengine/purego v0.10.2` |
| 지원 범위 | macOS/Linux amd64·arm64, Windows amd64(`CC="zig cc"`), 크로스 컴파일 가능 | macOS/Linux/Windows amd64·arm64, 크로스 컴파일 가능 |

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
    .link = .purego,
});
_ = purego_bindings.addStandardSteps(b, .{ .name_prefix = "purego" });
```

`.link = .purego`는 하나의 값이므로 "purego + 정적 링크" 같은 조합은 표현되지 않는다.
지원하지 않는 타깃은 빌드 그래프를 만드는 시점에 실패한다. 한 저장소에서 두 백엔드를 모두 제공하려면 위처럼
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

- 호스트 플랫폼이 지원 대상(macOS/Linux/Windows, amd64/arm64)인지
- `go.mod`가 검증된 purego 버전을 요구하는지
- 설치된 공유 라이브러리가 존재하고 플랫폼 로더로 실제 로드되는지

크로스 빌드에서는 호스트가 외래 아티팩트를 로드할 수 없으므로 마지막 검사를 실패가
아니라 `SKIP`으로 보고한다. 나머지 검사는 그대로 수행하므로
`zig build purego-go-verify -Dtarget=x86_64-windows`는 통과한다. 아티팩트의 실행 검증은
타깃 호스트에서 해야 한다. zigo 자신의 CI가 그렇게 한다. Ubuntu 잡이
`examples/07-event-queue`의 Windows DLL을 크로스 빌드해 아티팩트로 올리고, Windows 잡이
그것을 내려받아 `ZIGO_LIBRARY_PATH`로 가리킨 뒤 07의 Go 스위트를 돌린다.

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
실패는 `errors.Is(err, ErrLibraryLoad)`로 판별한다. 경로·심볼·원인은 `*LibraryError`에
담기며 플랫폼 로더 오류를 `Unwrap`으로
노출한다. 로드에 성공한 핸들은 프로세스 수명 동안 닫지 않는다. 생성된 함수 포인터와
살아 있는 네이티브 핸들 때문에 안전한 unload가 불가능하기 때문이다. 로드 전에 바인딩을
호출하면 같은 진단 메시지로 panic한다.

`DefaultLibraryName`은 생성 시점이 아니라 실행 시점에 `runtime.GOOS`로 결정된다. 따라서
커밋된 생성물은 macOS, Linux, Windows에서 동일하며, 생성물 최신 상태 검사도 세 플랫폼에서
같은 결과를 낸다.

| `GOOS` | `DefaultLibraryName` |
|---|---|
| `darwin` | `lib<name>_zigo.dylib` |
| `linux` | `lib<name>_zigo.so` |
| `windows` | `<name>_zigo.dll` |

Windows 파일명에는 관례대로 `lib` 접두사가 붙지 않는다. OS별 로더 primitive는 build
tag로 나뉜 `raw_load_posix_gen.go`(`//go:build !windows`)와
`raw_load_windows_gen.go`(`//go:build windows`)에 있고, 각각 `openLibrary`,
`closeLibrary`, `resolveSymbol`을 똑같이 정의한다. POSIX는 purego의
`Dlopen`/`Dlsym`/`Dlclose`를, Windows는 표준 라이브러리
`syscall.LoadLibrary`/`GetProcAddress`/`FreeLibrary`를 쓴다. purego v0.10.2는 Windows
로딩 API를 공개하지 않으므로(`dlfcn.go`가 POSIX 전용이고 `loadSymbol`은 비공개) 이
선택은 모듈 의존성을 늘리지 않는다. `purego.NewCallback`과 `RegisterFunc`는 Windows를
Tier 1으로 지원하므로 콜백 경로는 공용 파일에 그대로 남는다. 후보 경로 결정,
`LoadLibrary`, `*LibraryError` 모양은 세 OS에서 동일하다.

## 로딩 정책 설정

`library_loading`으로 라이브러리를 어디서 어떤 순서로 찾을지, 첫 호출에 자동으로 로드할지,
로더를 공개 API로 노출할지를 선언한다. 기본값은 위에서 설명한 동작 그대로다.

```zig
.library_loading = .{
    // 환경 변수 다음에 이 순서로 시도한다. 파일이 아니면 디렉터리로 보고
    // 플랫폼 라이브러리 이름을 붙인다.
    .search_paths = &.{ "${EXECUTABLE_DIR}", "${EXECUTABLE_DIR}/../lib", "/opt/myapp/lib" },
    // 첫 바인딩 호출에서 위 후보를 한 번 시도한다.
    // 첫 호출에서 자동으로 로드하고, 공개 패키지에서
    // LoadLibrary/LibraryLoaded/DefaultLibraryName을 감춘다.
    .loader = .automatic_internal,
    // 기본값은 패키지 전용 이름과 공용 이름 두 개다.
    .env_vars = &.{ "MYAPP_LIBRARY_PATH" },
},
```

| 필드 | 기본값 | 설명 |
|---|---|---|
| `search_paths` | 없음 | 환경 변수 다음에 순서대로 시도할 위치 |
| `env_vars` | `null` | `null`은 `ZIGO_<PACKAGE>_LIBRARY_PATH`와 `ZIGO_LIBRARY_PATH`. 빈 목록은 환경 변수를 보지 않음 |
| `loader` | `.explicit` | 누가 로드를 시작하는지, 로더가 공개 API인지 |

`loader`는 세 값을 가진다.

| 값 | 뜻 |
|---|---|
| `.explicit` | 호출자가 `LoadLibrary`를 직접 부른다 |
| `.automatic` | 첫 바인딩 호출에서 자동 로드하고 `LoadLibrary`도 그대로 노출한다 |
| `.automatic_internal` | 자동 로드하고 로더를 공개 API에서 감춘다 |

"자동 로드도 안 하고 로더도 노출하지 않는" 조합은 아무도 라이브러리를 로드할 수 없으므로
축을 하나로 접어 아예 표현되지 않게 했다. raw 패키지를 public 패키지와 같은 위치에 둔
경우 `.automatic_internal`은 raw 로더 이름을 내보내지 않는 방식으로 지켜진다.

`library_loading`은 `.link = .purego`에서만 쓸 수 있다. 잘못된 조합은 빌드
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

`.loader = .automatic` 또는 `.automatic_internal`이면 첫 바인딩 호출이 후보 목록을
**한 번** 시도한다. 성공하면 이후
호출은 그대로 진행되고, 모두 실패하면 모든 후보를 담은 오류로 panic한다. 공개 API가 오류를
반환하지 않는 형태이므로 panic 외에 다른 선택지가 없다. 실패 후에도 `LoadLibrary`가 노출된
`.automatic` 구성이라면 다른 경로로 명시적 재시도를 할 수 있다.

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
  Linux `lib<name>_zigo.so`, Windows `<name>_zigo.dll`이다. 설치 위치는 Zig의
  관례를 따른다. `zig build go-lib`은 DLL을 `zig-out/bin`에, 나머지는
  `zig-out/lib`에 설치한다. 경로를 직접 조립하지 말고 `GoBindings.library_path`를
  읽으면 플랫폼과 무관하게 실제 설치 경로를 얻는다.
- 배포 대상 OS·아키텍처 조합마다 아티팩트를 하나씩 만들지만, 호스트는 하나면 된다.
  `-Dtarget`을 넘기면 그 타깃으로 라이브러리를 빌드한다. 리플렉션 파이프라인은 항상
  호스트로 빌드해 실행하고, `-Dtarget`은 라이브러리·shim·헤더에만 적용된다.

  ```bash
  # 한 macOS/Linux 호스트에서 세 플랫폼 아티팩트를 모두 만든다.
  zig build purego-go-lib -Dtarget=x86_64-windows   # -> zig-out/bin/<name>_zigo.dll
  zig build purego-go-lib -Dtarget=aarch64-windows  # -> zig-out/bin/<name>_zigo.dll
  zig build purego-go-lib -Dtarget=x86_64-linux-gnu # -> zig-out/lib/lib<name>_zigo.so
  zig build purego-go-lib                           # 호스트 네이티브
  ```

  생성되는 Go 트리는 타깃과 무관하게 동일하다. 타깃에 따라 달라지는 진단도 없으므로
  어느 호스트에서 어느 타깃으로 생성해도 커밋된 트리는 바이트 단위로 같다.

  cgo 백엔드를 `CC="zig cc -target x86_64-windows"`로 크로스 링크하는 방법은 검증하지
  않았다. 후속 작업 후보일 뿐 지원 대상이 아니다.
- 크로스 컴파일에서 리플렉션은 **호스트**의 타입 레이아웃을 기록한다. 지원 타깃은 모두
  64비트 리틀엔디언이므로 고정폭 정수·실수·포인터는 일치하지만, `c_long`·`c_ulong`은
  Windows에서 4바이트, Linux·macOS에서 8바이트로 갈린다. 생성된 shim은 mirror하는 모든
  `extern struct`의 크기·정렬·필드 오프셋을 comptime으로 고정하므로 어긋나면 타깃
  컴파일이 다음처럼 실패한다.

  ```text
  error: zigo ABI guard: @sizeOf(Sizes) is 8 on this target, but zigo reflected 16
  on the build host. ... A C type whose width varies by target, such as c_long or
  c_ulong, is the usual cause; replace it with a fixed-width type.
  ```

  구조체 밖의 스칼라는 별도 가드가 필요 없다. 파라미터와 콜백은 Zig 자신의 타입
  오류로 즉시 걸리고, 반환값과 union payload는 shim 경계에서 손실 없이 넓혀진다.
  반면 타깃에 따라 export 자체가 달라지는 바인딩 표면은 지원하지 않는다. 리플렉션은
  호스트 표면 하나만 보고, 가드는 레이아웃 차이를 잡지 표면 차이를 잡지 못한다.
- Go 애플리케이션 쪽은 그대로 크로스 컴파일된다. 생성된 purego 패키지에는 cgo가 없으므로
  어떤 호스트에서든 C 툴체인 없이 빌드할 수 있고, 실행 시 짝이 되는 라이브러리만
  옆에 두면 된다.

  ```bash
  cd go-purego && GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build ./...
  ```
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
받는 네이티브 진입점에 `_purego_v2` 접미사를 붙인다. cgo 백엔드의 심볼과 트램폴린은
그대로 유지되므로 기존 cgo ABI는 바뀌지 않는다.

접미사의 버전이 곧 콜백 ABI의 버전이다. 콜백 ABI가 바뀌면 접미사가 올라가므로, 오래된
라이브러리와 새로 생성한 Go를 섞으면 비트를 잘못 읽는 대신 로드 시점에 심볼을 찾지
못하고 실패한다. `zigo-gen report`는 이 버전을 `callback ABI:` 줄에 출력한다.

- 부동소수 콜백 파라미터는 같은 폭의 정수에 IEEE-754 비트 패턴으로 실려 건너간다.
  `f64`는 `uint64_t`, `f32`는 `uint32_t`다. Windows의 `purego.NewCallback`은
  `syscall.NewCallback`을 그대로 감싸고, 그 뒤의 `compileCallback`은 386이 아닌
  아키텍처에서 부동소수 인자를 거부하기 때문이다(값이 트램폴린이 스필하지 않는
  부동소수 레지스터로 전달된다). 변환은 양쪽 끝에서 일어난다. 네이티브 쪽은 여전히
  진짜 부동소수로 호출하고, shim이 생성한 정적 thunk가 `@bitCast`해서 Go dispatcher로
  넘기며, dispatcher가 `math.Float64frombits`로 되돌린다. Go에서 쓰는 콜백 타입은
  그대로 `float64`다.
- 이 lowering은 모든 플랫폼에 동일하게 적용된다. 타깃마다 다른 ABI를 내보내면 커밋된
  생성 트리가 호스트·타깃에 따라 달라지기 때문이다.

- 고유한 콜백 시그니처마다 영구 dispatcher를 하나 만든다. `purego.NewCallback` 슬롯은
  회수할 수 없으므로 콜백 값마다 네이티브 콜백을 만들지 않는다.
- 콜백 값은 동기화된 정수 토큰 레지스트리에 저장한다. borrowed 토큰은 호출이 끝나면,
  retained 토큰은 `Close`나 자동 cleanup에서 삭제된다. 삭제는 진행 중인 호출을 기다린다.
- 콜백에서 발생한 panic은 부호 있는 32비트 결과를 가진 콜백 ABI에서 `-3`으로, 이미
  해제된 토큰 호출은 `-4`로 결정적으로 변환된다. `-3`은 native가 정리하고 반환할 수 있게
  하는 값일 뿐이고, 호출이 돌아오면 생성된 함수가 그 panic을 `*CallbackPanicError`로 다시
  일으킨다 — cgo 백엔드와 같은 규칙이다.

### `std.Io` 스트림

`*std.Io.Writer`/`*std.Io.Reader` 파라미터도 같은 메커니즘을 쓴다. 방향마다 영구
dispatcher가 하나씩 있고(`StreamWriterCallbackPointer`, `StreamReaderCallbackPointer`),
스트림 값은 사용자 콜백과 같은 토큰 레지스트리에 들어간다. 스트림은 항상 call-scoped이므로
토큰은 호출이 끝나면 삭제된다. 결과는 `i32`라 `ZIGO014` 제약을 그대로 만족한다. 스트림
파라미터를 받는 진입점도 `_purego_v2` 접미사를 받는다.

## 알려진 제약

- purego는 v1 이전 베타 소프트웨어다. zigo는 `v0.10.2`를 고정해 생성·검증하고, 사용은
  생성된 raw 파일에만 격리한다. 다른 버전을 요구하는 `go.mod`는 `go-doctor`가 경고한다.
- 지원 범위는 네이티브 macOS/Linux/Windows amd64·arm64다. 모바일과 purego Tier 2
  타깃은 후속 작업이다. Windows에서는 cgo 백엔드도 `CC="zig cc"`로 쓸 수 있으므로
  (amd64, gnu ABI), 이 표의 선택 기준은 Windows에서도 다른 플랫폼과 같다.
- 콜백 결과는 `void`나 `i32`만 지원하고, 그 밖의 타입은 `ZIGO014`로 거부한다.
  값은 userdata로 돌려준다.
- 정적 링크는 cgo 전용이다.
- Go race detector는 여전히 cgo를 요구하므로 `CGO_ENABLED=0` 테스트에서는 사용할 수 없다.
  race 커버리지는 cgo 백엔드 테스트에서 확보한다. Windows purego 잡도 마찬가지다.
- zigo가 `go.mod`를 새로 만들 때만 purego 요구사항을 기록한다. 이미 있는 모듈은 직접
  `go get github.com/ebitengine/purego@v0.10.2`를 실행한다.

아티팩트 계약의 세부 사항은 설계 문서
[공유 라이브러리 계약](.agent/design/06-shared-library-contract.md)에 있다.
