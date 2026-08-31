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

> 한 빌드에 두 백엔드를 등록하면 두 아티팩트가 같은 `zig-out/lib`에 설치된다. 이때
> 공유 라이브러리가 cgo 링크에서 정적 아카이브를 가리므로, 두 백엔드를 같은 트리에서
> 검증할 때는 `zig build purego-go --prefix zig-out-purego`처럼 설치 위치를 분리하거나
> 백엔드마다 깨끗한 `zig-out`에서 검사한다. CI는 백엔드별 잡으로 분리해 이 문제를
> 피한다. 설치 위치를 옮겼다면 테스트에는 `ZIGO_LIBRARY_PATH`로 실제 경로를 알려준다.

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

`LoadLibrary(path)`의 경로 결정 순서는 다음과 같다.

1. 인자로 받은 경로
2. 환경 변수 `ZIGO_LIBRARY_PATH`
3. `DefaultLibraryName` (플랫폼 기본 파일명; 플랫폼 로더의 검색 경로에서 찾는다)

로딩은 원자적이다. 필요한 심볼을 모두 해석한 뒤에만 호출 표면을 공개하므로, 실패한
로드는 부분적으로 호출 가능한 패키지를 남기지 않고 다른 경로로 재시도할 수 있다.
실패는 경로·심볼·원인을 담은 `*LibraryError`로 반환되며 플랫폼 로더 오류를 `Unwrap`으로
노출한다. 로드에 성공한 핸들은 프로세스 수명 동안 닫지 않는다. 생성된 함수 포인터와
살아 있는 네이티브 핸들 때문에 안전한 unload가 불가능하기 때문이다. 로드 전에 바인딩을
호출하면 같은 진단 메시지로 panic한다.

`DefaultLibraryName`은 생성 시점이 아니라 실행 시점에 `runtime.GOOS`로 결정된다. 따라서
커밋된 생성물은 macOS와 Linux에서 동일하며, 생성물 최신 상태 검사도 두 플랫폼에서 같은
결과를 낸다.

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

아티팩트 계약의 세부 사항은 [공유 라이브러리 계약](../shared-library.md)에 있다.
