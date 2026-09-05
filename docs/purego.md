# 공유 라이브러리와 purego

purego를 선택하면 Go 프로그램을 `CGO_ENABLED=0`으로 빌드할 수 있습니다.
대신 실행할 OS·아키텍처에 맞는 Zig 공유 라이브러리를 함께 배포하고, 사용 전에 로드해야 합니다.

기본 cgo 설정을 아직 실행해 보지 않았다면 [시작 가이드](getting-started.md)를 먼저 보세요.
이 문서는 설정 → 생성 → 로딩 → 배포 순서로 설명합니다.
이미 설정을 마쳤다면 [로딩 정책](#로딩-정책-설정)이나 [문제 해결](#문제-해결)로 이동하세요.

| 선택 기준 | cgo | purego |
|---|---|---|
| Go 빌드에 C 컴파일러 사용 | 필요 | 불필요 |
| native 라이브러리 연결 | 빌드 시 링크 | 실행 시 로드 |
| 정적 링크 | 지원 | 미지원 |
| 공유 라이브러리 배포 | `.cgo_dynamic` 선택 시 필요 | 항상 필요 |

바인딩 함수·타입의 사용법은 공통입니다. purego에는 로더 API와
`github.com/ebitengine/purego v0.10.2` 의존성이 추가됩니다.
지원 타깃은 macOS·Linux·Windows의 amd64·arm64입니다.
플랫폼 전체 조건은 [지원 환경](limitations.md#지원-환경)을 참고하세요.

## 빌드 설정

`build.zig`에서 `.link = .purego`를 지정합니다. 아래는 시작 가이드의 모듈·타깃 설정을
사용하는 바인딩 등록 부분입니다.

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

이 문서의 명령은 위 설정이 있는 프로젝트 루트에서 실행합니다.
`name_prefix`를 바꾸거나 생략했다면 명령의 스텝 이름도 맞춰 바꾸세요.

cgo도 함께 제공하려면 별도의 `go_dir`·`go_module`로 등록합니다.
[04-callback](../examples/04-callback/README.md)이 두 백엔드를 함께 구성하는 예제입니다.
기본 파일명을 사용하면 cgo 정적 archive와 purego 공유 라이브러리·헤더는 서로 겹치지 않습니다.

## 재현 절차

기존 Go 모듈에 purego를 추가하는 경우, 생성 전에 해당 모듈에서 의존성을 추가하세요.

```bash
(cd go-purego && go get github.com/ebitengine/purego@v0.10.2)
```

아직 `go.mod`가 없다면 이 단계는 건너뜁니다. zigo가 새 모듈을 만들 때는 버전 요구사항을
기록하지만 기존 `go.mod`를 수정하지는 않습니다.

공유 라이브러리와 Go 소스를 생성하고 의존성을 준비합니다.

```bash
zig build purego-go
(cd go-purego && go mod tidy)
zig build purego-go-verify
```

`purego-go`는 기본적으로 `zig-out/lib`에 라이브러리를 설치합니다.
`purego-go-verify`는 생성물, 설치 아티팩트, Go 환경과 라이브러리 로딩을 검사합니다.
`abi_base`가 있으면 ABI 검사도 포함합니다. Go 테스트 자체는 실행하지 않습니다.

다음 절의 로딩 코드를 애플리케이션이나 테스트 초기화에 추가한 뒤 테스트하세요.

```bash
(cd go-purego && CGO_ENABLED=0 go test ./...)
```

저장소 예제는 로딩 초기화가 이미 준비되어 있습니다.
처음 만든 패키지에서는 환경 변수만 설정해도 자동으로 로드된다고 가정하지 마세요.
자동 로딩을 원하면 [로딩 정책](#자동-로딩)을 별도로 선택해야 합니다.

## 라이브러리 로딩

기본 정책은 명시적 로딩입니다. `error`를 반환하는 초기화 함수 안에서 다음처럼 호출합니다.
예제의 `mylib`는 생성된 공개 패키지의 import 이름입니다.

```go
if err := mylib.LoadLibrary("/opt/myapp/lib/" + mylib.DefaultLibraryName); err != nil {
    return err
}
// 이 시점부터 바인딩 함수를 호출할 수 있습니다.
```

`LibraryLoaded()`는 로딩 완료 여부를 반환합니다.
필요한 심볼을 모두 찾은 뒤에만 호출 가능한 상태가 되므로, 실패한 로드는 일부 함수만
사용 가능한 상태를 남기지 않습니다. 명시적 로딩 실패 뒤에는 다른 경로로 재시도할 수 있습니다.

주의: 기본 정책에서 로드 전에 바인딩 함수를 호출하면 panic합니다.
성공적으로 로드한 라이브러리는 프로세스 종료까지 유지되며 unload·hot reload는 제공하지 않습니다.

### 기본 파일명

`DefaultLibraryName`은 실행 중인 OS에 따라 정해집니다.

| OS | 기본 파일명 |
|---|---|
| macOS | `lib<name>_zigo.dylib` |
| Linux | `lib<name>_zigo.so` |
| Windows | `<name>_zigo.dll` |

`install.library_name`을 바꾸면 같은 이름이 로더에도 반영됩니다.
사용자 정의 빌드 스텝에서는 `GoBindings.library_path`로 실제 설치 경로를 확인할 수 있습니다.

## 로딩 정책 설정

`library_loading`은 purego 전용 옵션입니다. 검색 경로·환경 변수·로딩 시점을 함께 설정합니다.
아래 예제는 실행 파일 옆의 라이브러리를 첫 호출에 자동으로 로드합니다.

```zig
.library_loading = .{
    .search_paths = &.{ "${EXECUTABLE_DIR}", "${EXECUTABLE_DIR}/../lib" },
    .env_vars = &.{ "MYAPP_LIBRARY_PATH" },
    .loader = .automatic,
},
```

| 필드 | 기본값 | 용도 |
|---|---|---|
| `search_paths` | 빈 목록 | 라이브러리 파일 또는 디렉터리 후보 |
| `env_vars` | `null` | 경로를 읽을 환경 변수 목록 |
| `loader` | `.explicit` | 로딩 시점과 공개 로더 API 선택 |

기본값에는 두 가지 규칙이 있습니다.

- `env_vars = null`은 기본 환경 변수 두 개를 사용합니다. 빈 목록 `&.{}`은 환경 변수를 사용하지 않습니다.
- `search_paths`가 비어 있고 `install.library_dir`이 `.lib`가 아니면, 공개 Go 패키지에서
  설치 디렉터리까지의 상대 경로를 기본 후보로 사용합니다. 비어 있지 않은 목록을 지정하면
  그 목록으로 대체합니다.

### 후보 순서

`LoadLibrary(path)`에 비어 있지 않은 경로를 넘기면 그 경로만 시도합니다.
빈 문자열을 넘기거나 자동 로딩을 사용하면 다음 순서로 찾습니다.

1. `env_vars`에 지정한 환경 변수 중 값이 있는 것
2. `search_paths`의 각 항목
3. `DefaultLibraryName`을 플랫폼 로더의 검색 경로에서 탐색

검색 항목이 플랫폼 라이브러리 확장자로 끝나면 파일로, 그렇지 않으면 디렉터리로 보고
기본 파일명을 붙입니다. `${EXECUTABLE_DIR}`는 실행 파일이 있는 디렉터리로 확장하며,
확인할 수 없으면 그 항목을 건너뜁니다.

`search_paths`에는 `:`를 쓸 수 없습니다. Windows의 `C:/...` 같은 드라이브 경로는
`LoadLibrary` 인자나 환경 변수로 전달하세요. 일반 상대 경로는 실행 시 작업 디렉터리에
따라 달라지므로 배포할 때 주의해야 합니다.

### 자동 로딩

| `loader` | 로딩 시작 | 공개 로더 API |
|---|---|---|
| `.explicit` | 사용자의 `LoadLibrary` 호출 | 있음 |
| `.automatic` | 첫 바인딩 호출 | 있음 |
| `.automatic_internal` | 첫 바인딩 호출 | 없음 |

자동 로딩은 후보 목록을 한 번 시도합니다. 모두 실패하면 `*LibraryError`로 panic합니다.
`.automatic`은 로더 API가 있으므로 실패 후 `LoadLibrary`로 명시적으로 재시도할 수 있습니다.
`.automatic_internal`은 `LoadLibrary`·`LibraryLoaded`·`DefaultLibraryName`을 공개하지 않습니다.

실행 예제는 [08-telemetry-hub](../examples/08-telemetry-hub/README.md)에 있습니다.

### 환경 변수 이름

기본값은 패키지 전용 이름이 먼저이고 공용 이름이 나중입니다.
예를 들어 `telemetry_hub` 패키지는 다음 두 변수를 사용합니다.

```text
ZIGO_TELEMETRY_HUB_LIBRARY_PATH
ZIGO_LIBRARY_PATH
```

한 프로세스에서 여러 바인딩을 쓰면 패키지 전용 변수로 각 라이브러리를 지정하세요.
실제 적용된 정책은 `zig build purego-go-report`로 확인합니다.

## 패키징과 배포

Go 실행 파일과 타깃에 맞는 공유 라이브러리를 함께 배포합니다.
native 라이브러리가 다른 동적 라이브러리에 의존하면 그 의존성도 준비해야 합니다.
Go 생성 소스와 `zigo/`는 커밋하고, 공유 라이브러리는 릴리스 아티팩트로 관리하세요.

### 크로스 컴파일

한 호스트에서 여러 타깃을 빌드할 수 있습니다. 아키텍처가 달라도 파일명이 같을 수 있으므로
타깃별 설치 prefix를 분리하세요.

```bash
zig build purego-go-lib -Dtarget=x86_64-windows -p zig-out/windows-amd64
zig build purego-go-lib -Dtarget=aarch64-windows -p zig-out/windows-arm64
zig build purego-go-lib -Dtarget=x86_64-linux-gnu -p zig-out/linux-amd64
```

예를 들어 첫 명령의 DLL은 `zig-out/windows-amd64/lib/`에 설치됩니다.
Go 애플리케이션도 같은 OS·아키텍처로 빌드하세요.

```bash
(cd go-purego && GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build ./...)
```

이 명령은 Go 패키지를 빌드합니다. 배포할 실행 파일이 필요하면 자신의 `main` 패키지와
`-o` 경로를 지정하세요.

리플렉션은 호스트에서 실행합니다. `c_long`처럼 타깃별 폭이 다른 타입은 고정 폭 타입으로
바꾸고, 타깃별 공개 선언이 다른 API는 해당 타깃에서 생성하세요.
[크로스 컴파일 제약](limitations.md#크로스-컴파일)을 함께 확인해야 합니다.

크로스 타깃의 doctor는 호스트에서 로드할 수 없는 라이브러리 검사를 `SKIP`합니다.
생성·컴파일 성공은 타깃에서의 실행 검증을 대신하지 않습니다.

### 보안 주의사항

라이브러리 로드는 native 코드 실행입니다. 사용자가 임의로 지정한 경로를 그대로 로드하지 마세요.

- 애플리케이션이 통제하는 디렉터리나 검증한 절대 경로를 사용합니다.
- 환경 변수를 통한 경로 변경을 막으려면 `.env_vars = &.{}`를 설정합니다.
- 배포 요구사항에 따라 로드 전에 서명·체크섬을 확인합니다.
- 잘못된 라이브러리를 로드했다면 프로세스를 재시작합니다.

## 콜백

purego도 Go 콜백을 지원합니다. 콜백 반환 타입은 `void` 또는 `i32`이며,
부동소수 인자는 지원합니다. 선언과 수명은 [콜백 가이드](bindings-callbacks.md)를 따릅니다.

콜백 진입점에는 `_purego_v2`가 붙습니다. native 라이브러리와 Go 생성물이 맞지 않으면
로딩 시 심볼을 찾지 못할 수 있으므로 두 결과를 함께 갱신하세요.
dispatcher·토큰·float 전달의 내부 계약은
[공유 라이브러리 계약](.agent/design/06-shared-library-contract.md)에 있습니다.

### 콜백이 돌려주는 Go error

`.go_error`를 켜면 Go 콜백이 반환한 오류를 `*CallbackError`로 전달합니다.
같은 ABI 시그니처의 콜백들은 이 설정을 공유합니다.
[오류 선언과 판별](bindings-callbacks.md#콜백이-돌려주는-go-error)을 참고하세요.

### 취소 플래그

`.cancel`은 purego에서도 `context.Context`와 연결됩니다. Zig 함수가 취소 플래그를
확인해야 하며 native 호출을 강제로 중단하지는 않습니다.
[취소 설정](bindings-streams.md#취소-cancel)과
[메모리 고정 계약](generated-abi.md#취소-플래그)을 참고하세요.

### `std.Io` 스트림

`io.Reader`·`io.Writer`도 지원합니다. 스트림은 호출 중에만 빌리며 호출 종료 후 보관할
수 없습니다. reader의 빠른 경로에서는 읽기 위치가 전진하지 않는다는 점도 cgo와 같습니다.
[스트림 가이드](bindings-streams.md)와 [실행 예제](../examples/11-io-streams/README.md)를 참고하세요.

## 문제 해결

| 증상 | 먼저 할 일 |
|---|---|
| purego 모듈 요구사항 누락 | Go 모듈에서 `go get github.com/ebitengine/purego@v0.10.2` |
| `go.sum` 관련 오류 | Go 모듈에서 `go mod tidy` |
| 라이브러리 파일을 찾지 못함 | 설치 경로와 `LoadLibrary` 인자 확인 |
| 필요한 심볼을 찾지 못함 | 같은 선언·버전에서 Go 소스와 native 라이브러리를 다시 생성 |
| 첫 함수 호출에서 로딩 panic | 명시적 로드 여부 또는 자동 로딩의 후보 경로 확인 |
| 크로스 빌드 doctor의 `SKIP` | 타깃 호스트에서 라이브러리를 실행해 검증 |

명시적 로드 실패는 `errors.Is(err, mylib.ErrLibraryLoad)`로 분류하고
`*mylib.LibraryError`에서 경로·심볼·원인을 확인합니다.
후보가 여러 개면 오류에 각 시도가 포함됩니다.

## 알려진 제약

- zigo는 purego `v0.10.2`를 기준으로 생성·검증합니다. 다른 버전은 doctor가 경고합니다.
- 모바일·32비트 타깃은 지원하지 않습니다.
- 정적 링크는 cgo 전용입니다.
- Go race detector는 cgo가 필요하므로 `CGO_ENABLED=0`에서는 실행할 수 없습니다.

전체 지원 조건은 [지원 범위와 제한사항](limitations.md), OS별 로더 파일 구조는
[생성 Go 코드의 내부 구조](generated-runtime.md#purego-로더-파일)에 있습니다.
