# 생성물과 CI 관리

Zig API나 `bindings.zig`를 바꾸면 Go 코드를 다시 생성하고, 생성된 소스와 메타데이터를 함께
커밋합니다. CI에서는 커밋된 생성물이 최신인지 검사한 뒤 네이티브 라이브러리를 빌드해 테스트합니다.

이 문서의 명령은 `addStandardSteps`를 등록한 프로젝트의 루트에서 실행합니다.
기본 Go 디렉터리는 `go`, 백엔드는 cgo로 가정합니다. purego도 생성물 관리 원칙은 같지만
[의존성 준비와 라이브러리 로딩](purego.md#재현-절차)이 추가로 필요합니다.

평소에는 아래 개발 순서와 커밋 표만 확인하면 됩니다. 새 CI를 설정한다면
[CI 권장 구성](#ci-권장-구성), 경로·백엔드를 바꿨다면
[경로나 선언을 바꾼 뒤](#경로나-선언을-바꾼-뒤)를 확인하세요.

## 일상 개발 순서

```bash
# Zig API나 bindings.zig를 수정한 뒤
zig build go
(cd go && go test ./...)
git diff
```

`go`는 Go 소스와 메타데이터를 갱신하고 네이티브 라이브러리·헤더를 설치합니다.
변경 전 생성물이 이미 오래되었는지 확인하려면 수정 전에 `zig build go-check`를 실행하세요.

생성된 `*_gen.go`는 직접 수정하지 않습니다. 사용자 편의 API나 테스트는 같은 패키지의 별도
`.go` 파일에 작성하세요. 생성 파일과 같은 이름은 피해야 합니다.

## 생성 파일

| 위치 | 내용 | 커밋 여부 |
|---|---|---|
| `go/<package-path>/*_gen.go` | 공개 Go API | 커밋 |
| `go/internal/raw/*_gen.go` | C 호출 또는 purego 로더 | 아래 예외를 제외하고 커밋 |
| `go/internal/lifecycle/lifecycle_gen.go` | 하위 패키지가 공유하는 수명 관리 코드 | 생성되면 커밋 |
| `go/**/zigo_link_inputs_gen.go` | 빌드 시 정적 링크 입력 | 제외 |
| `go/go.mod`, `go/go.sum` | Go 모듈과 의존성 | 존재하는 파일을 커밋 |
| `zigo/semantic.json` | 바인딩 계약 | 커밋 |
| `zigo/errors.lock.json` | Zig 오류 이름과 정수 코드의 대응 | 커밋 |
| `zig-out/` | 네이티브 라이브러리와 헤더 | 제외 |

`<package-path>`는 기본적으로 공개 패키지 이름입니다. `go_package_path = "."`이면
공개 파일을 `go/` 루트에 만듭니다. raw 경로는 `raw_package`로 정하며, 공개 패키지와
같게 두면 두 계층이 같은 디렉터리에 생성됩니다.

선언이 없는 파일은 생성되지 않습니다. 예를 들어 enum이 없는 바인딩에는
`<package>_enums_gen.go`가 없습니다. 파일별 세부 역할은
[생성 Go 코드의 내부 구조](generated-runtime.md#생성-파일의-역할)에 있습니다.

### 정적 링크 입력 파일의 예외

별도 정적 라이브러리를 링크하는 cgo 구성에서는 `zigo_link_inputs_gen.go`가 생깁니다.
이 파일은 `go-check`의 비교·오래된 파일 판정에서 제외되며, 빌드 스텝이 갱신합니다.
프로젝트의 `.gitignore`에 다음 패턴을 추가하세요.

```gitignore
**/zigo_link_inputs_gen.go
zig-out/
.zig-cache/
```

### 네이티브 라이브러리 위치

기본 설치 경로는 모든 OS에서 `zig-out/lib`입니다.

| 백엔드 | 기본 라이브러리 이름 |
|---|---|
| cgo 정적 링크 | `lib<name>_zigo.a` (Windows 포함) |
| cgo 동적 링크 / purego — macOS | `lib<name>_zigo.dylib` |
| cgo 동적 링크 / purego — Linux | `lib<name>_zigo.so` |
| cgo 동적 링크 / purego — Windows | `<name>_zigo.dll` |

헤더는 기본 `zig-out/include/zigo_<name>.h`이며, purego는
`zigo_<name>_purego.h`를 사용합니다. 위치와 이름을 바꿨다면
`GoBindings.library_path`에서 실제 경로를 확인하세요.
설정 방법은 [설치 위치](configuration.md#설치-위치), 배포 방법은 [purego 가이드](purego.md)에 있습니다.

## CI 권장 구성

새 체크아웃에서 생성물을 검사하고 Go 테스트를 실행하는 기본 구성입니다.

```bash
zig build go-check go-lib
(cd go && go test ./...)
```

`go-check`는 커밋된 Go 생성물과 현재 선언을 비교합니다. 필요한 파일이 없거나, 내용이
다르거나, 더 이상 생성되지 않는 zigo 파일이 남아 있으면 실패합니다.
네이티브 코드는 빌드하지만 라이브러리 설치까지 보장하지 않으므로 `go-lib`를 함께 실행합니다.

환경 진단까지 묶으려면 다음을 사용하세요.

```bash
zig build go-verify
(cd go && go test ./...)
```

`go-verify`는 `go-check`, `go-lib`, `go-doctor`와 설정된 `abi-check`를 포함합니다.
Go 테스트 자체는 실행하지 않으므로 별도로 실행해야 합니다.

`go-check`는 커밋 대상 Go 소스를 갱신하지 않습니다. 다만 위의 정적 링크 입력 파일은
생성하거나 갱신할 수 있습니다.

## ABI와 메타데이터 관리

독립 배포한 이전 버전과 호환성을 유지해야 한다면 `abi_base`에 비교할 Git ref를 지정하고
`zig build abi-check`를 실행합니다. 이 설정이 있으면 `go-verify`에도 포함됩니다.
설정하지 않으면 `abi-check` 스텝은 등록되지 않습니다.

`go-check`는 Go 생성 파일을 비교하며, `zigo/` 메타데이터의 최신 상태까지 검사하지 않습니다.
`zig build go` 이후 Go 소스와 메타데이터 변경을 함께 리뷰하세요.
`errors.lock.json`의 기존 오류 코드는 재사용하거나 바꾸지 않습니다.

타입이나 소유권을 바꾸기 전에는 [제한사항](limitations.md#abi-호환성)을 확인하세요.
C 표현과 메타데이터 필드의 상세 의미는 [생성 ABI 참조](generated-abi.md)에 있습니다.

## 경로나 선언을 바꾼 뒤

같은 `go_dir` 안에서 raw 패키지 경로·백엔드·노출할 선언을 바꾸면
`zig build go`가 이전 zigo 생성 파일을 자동 정리합니다.
생성 표시가 없는 사용자 파일은 보존합니다.

`go_dir` 자체를 옮겼다면 이전 디렉터리는 자동 정리 범위 밖입니다. 사용자 파일을 확인한 뒤
별도로 정리하세요. `zigo_link_inputs_gen.go`도 자동 정리에서 제외됩니다.

검증·렌더링 실패 시 기존 생성 트리는 유지됩니다. 최종 파일 쓰기 중 디스크 오류나 전원 차단이
발생한 경우에는 일부만 갱신될 수 있으므로 원인을 해결한 뒤 다시 생성하고 diff를 확인하세요.

## 진단 사용법

| 확인할 문제 | 실행할 명령 |
|---|---|
| Go 버전, `gofmt`, cgo·C 컴파일러, purego 라이브러리 | `zig build go-doctor` |
| 최종 Go 이름, C 심볼, 소유권·수명 결정 | `zig build go-report` |
| 공개 Zig API 중 노출·제외·누락된 함수 | `zig build go-coverage` |
| `ZIGO...` 생성 오류의 의미 | [생성기 진단](diagnostics.md) 참고 |

cgo doctor는 네이티브 타깃과 C 컴파일러 환경을 검사합니다. purego doctor는 공유 라이브러리를
먼저 설치하고 실제로 로드할 수 있는지 확인합니다. 크로스 빌드에서의 차이는
[지원 환경](limitations.md#지원-환경)을 참고하세요.

## 표준 빌드 스텝

| 스텝 | 역할 | 소스 트리 변경 |
|---|---|---|
| `go` | Go 생성물·메타데이터 갱신, 네이티브 라이브러리·헤더 설치 | 있음 |
| `go-check` | Go 생성물 최신 상태 검사 | 정적 링크 입력 파일만 가능 |
| `go-lib` | 네이티브 라이브러리·헤더 설치 | 정적 링크 입력 파일만 가능 |
| `go-report` | 바인딩 결정 설명 | 없음 |
| `go-doctor` | 실행 환경 진단 | 없음 |
| `go-coverage` | 공개 API 바인딩 현황 출력 | `coverage_json` 지정 시 보고서 기록 |
| `go-verify` | 검사·설치·진단 집계 | 정적 링크 입력 파일만 가능 |
| `abi-check` | `abi_base`와 호환성 비교 | 없음 |

`name_prefix = "admin"`이면 `admin-go`, `admin-go-check`처럼 접두사가 붙습니다.
기본 `zig build`도 네이티브 라이브러리와 헤더를 설치합니다. 상위 빌드에서 설치를 별도로
관리한다면 `addStandardSteps`에 `.install_library_by_default = false`를 지정하세요.
