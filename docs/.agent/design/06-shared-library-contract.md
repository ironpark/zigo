# 공유 라이브러리 계약

이 문서는 native 아티팩트와 생성 로더 사이의 내부 계약입니다. 빌드·배포 절차와 로딩
설정 예제는 [공유 라이브러리와 purego](../../purego.md)를 참고하세요.

## 빌드 선택과 설치 위치

공개 옵션 `Options.link`는 `.cgo_static`, `.cgo_dynamic`, `.purego` 중 하나입니다.
뒤의 두 선택지는 공유 라이브러리를 만듭니다.

기본 native 파일명은 macOS의 `lib<name>_zigo.dylib`, Linux의 `lib<name>_zigo.so`,
Windows의 `<name>_zigo.dll`입니다. 기본 설치 디렉터리는 `zig-out/lib`이며
`install.library_dir`로 바꿀 수 있습니다. Windows DLL도 이 설정을 따릅니다.

`GoBindings.lib`는 컴파일 스텝, `install_library`는 설치 스텝입니다.
`library_filename`과 `library_path`는 실제 아티팩트의 이름과 설치 경로를 제공합니다.
사용자 정의 스텝은 플랫폼 이름을 다시 조합하기보다 이 값을 사용해야 합니다.

정적 cgo 라이브러리와 purego 공유 라이브러리는 같은 prefix에 설치할 수 있습니다.
정적 링크는 archive 경로를 사용하고 purego 헤더에는 `_purego` 접미사가 붙습니다.
서로 다른 타깃의 빌드는 같은 파일명을 덮어쓸 수 있으므로 prefix를 분리하세요.

## 로더

purego는 macOS·Linux·Windows의 amd64·arm64를 지원합니다. 라이브러리는 타깃별로
빌드하며, 크로스 컴파일된 아티팩트의 실행 검증은 해당 타깃에서 수행합니다.

기본 정책에서는 바인딩 호출 전에 `LoadLibrary`를 호출합니다. 자동 로딩과 공개 로더 API를
숨기는 정책은 `library_loading`으로 선택합니다. 후보 경로와 환경 변수의 우선순위,
경로 검증과 실패 동작은 [로딩 가이드](../../purego.md)에 정의되어 있습니다.

로더는 필요한 심볼을 모두 찾은 뒤 호출 가능한 상태를 게시합니다. 성공적으로 로드된
라이브러리는 프로세스 종료까지 유지되며 hot reload를 제공하지 않습니다.

새 `go.mod`를 생성하면 purego 버전 요구사항도 기록합니다. 기존 모듈의 의존성을 임의로
수정하지 않으므로 사용자가 해당 요구사항과 `go.sum`을 준비해야 합니다.

## purego 콜백 ABI

콜백이 있는 purego 진입점에는 `_purego_v2` 접미사가 붙습니다. C 시그니처는 callback
함수 포인터와 정수 userdata를 받으므로 native 라이브러리가 Go의 `//export` trampoline
심볼에 의존하지 않습니다. cgo는 기존 진입점과 생성 trampoline을 사용합니다.

접미사의 버전은 콜백 ABI 버전입니다. 오래된 라이브러리를 새 Go 코드와 결합하면 잘못된
표현으로 호출하기 전에 심볼 해석이 실패하게 합니다. float 콜백 인자는 같은 폭의 정수에
IEEE-754 비트를 담아 전달하고 양쪽 adapter가 변환합니다. 공개 Go 콜백 인자는 float를
유지합니다. purego 콜백 반환은 `void` 또는 signed 32-bit 정수로 제한합니다.

고유 시그니처마다 native dispatcher를 만들고, 개별 Go 콜백은 동기화된 정수 토큰 레지스트리로
찾습니다. borrowed·retained 수명과 오류 전달의 사용자 계약은
[콜백과 오류 처리](../../bindings-callbacks.md)에 있습니다.

## 검증

`go-lib`는 아티팩트를 설치합니다. `go-verify`는 생성물 최신 상태, 설치와 환경 진단,
설정된 경우 ABI 검사를 묶습니다. purego doctor는 의존성과 native 로딩을 검사하며,
호스트에서 실행할 수 없는 크로스 타깃의 로딩 검사는 건너뜁니다.

저장소의 아래 도구는 지원되는 POSIX 호스트에서 실제 export 심볼과 로딩을 검사합니다.

```sh
tests/inspect_shared_library.sh <library> <symbol>...
zig build shared-library-smoke -- <library> <symbol>...
```

실행 명령과 플랫폼별 차이는 [프로젝트 개발](../../development.md),
실제 검증 매트릭스는 [CI](../../../.github/workflows/ci.yml)를 참고하세요.
