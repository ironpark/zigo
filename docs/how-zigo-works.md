# zigo의 작동 방식

zigo는 Zig 구현을 직접 변경하거나 Zig 타입을 그대로 Go 메모리에 노출하지 않습니다.
사용자가 선택한 공개 API를 언어 사이에서 안전하게 전달할 수 있는 계약으로 낮춘 뒤 두 언어의
코드를 함께 생성합니다.

## 네 가지 입력과 출력

```text
                 build.zig
                     │
Zig public API ── bindings.zig
         │           │
         └──── zigo generator
                     │
       ┌─────────────┼──────────────┐
       ▼             ▼              ▼
  Zig ABI shim   Go packages     metadata
  + C header     raw + public    semantic + ABI
```

- Zig API는 실제 구현과 타입을 정의합니다.
- `bindings.zig`는 그중 Go에 공개할 선언과 변환 규칙을 선택합니다.
- `build.zig`는 출력 위치, Go module, 백엔드와 설치 정책을 정합니다.
- zigo는 이 입력을 검증한 뒤 Zig shim, C header, Go 코드와 metadata를 생성합니다.

## `bindings.zig`는 구현이 아니라 공개 계약입니다

라이브러리 코드는 Go를 알 필요가 없습니다. 다음 선언은 기존 Zig 함수 하나를 선택합니다.

```zig
const api = zigo.scope(library);

pub const bindings = zigo.define(.{
    .root = library,
    .declarations = &.{api.func("add", .{})},
});
```

필요한 경우 함수 이름, parameter 의미, 생성자와 소멸자, callback 수명이나 결과 표현을
추가로 선언합니다. zigo는 Zig 선언과 binding metadata가 모순되면 코드를 만들기 전에
`ZIGO...` 진단으로 거부합니다.

## raw 계층과 public 계층

생성 Go module에는 역할이 다른 두 계층이 있습니다.

| 계층 | 역할 | 직접 사용 여부 |
|---|---|---|
| raw package | C ABI 호출, pointer와 scalar 변환 | 보통 import하지 않음 |
| public package | Go 이름, error, handle, callback과 interface | 애플리케이션이 사용 |

예를 들어 Zig error union은 raw 상태 코드로 전달되지만 공개 패키지에서는 Go `error`로
보입니다. opaque pointer는 public package에서 동시 호출과 `Close`를 관리하는 handle이
됩니다.

## 수명은 API의 일부입니다

언어 경계를 넘는 값은 복사 여부와 소유자를 명확히 해야 합니다.

- scalar와 작은 값 struct는 값으로 전달됩니다.
- 입력 string과 slice는 호출 동안만 빌립니다.
- caller-owned 결과는 생성 코드가 복사하거나 정해진 release 함수로 해제합니다.
- opaque 객체는 Go handle이 소유하고 `Close`로 해제합니다.
- borrowed handle은 부모 객체보다 오래 사용할 수 없습니다.
- retained callback은 native 코드가 보관하는 동안 Go registry에 유지됩니다.

세부 계약은 값, 버퍼, 객체와 callback 가이드에서 기능별로 설명합니다.

## 생성과 검사는 다른 작업입니다

`addStandardSteps`가 등록하는 기본 단계는 의도가 구분되어 있습니다.

| 단계 | 역할 |
|---|---|
| `go` | 생성물을 갱신하고 현재 타깃의 native library를 빌드 |
| `go-check` | 커밋한 생성물이 최신인지 검사 |
| `go-lib` | native library와 header를 설치 |
| `go-doctor` | Go와 native toolchain 전제 검사 |
| `go-report` | 최종 binding 결정 설명 |
| `go-coverage` | 공개 Zig 함수의 binding 포함 여부 보고 |
| `abi-check` | 설정한 기준과 ABI 호환성 비교 |
| `go-verify` | 검사, toolchain, library와 선택적 ABI 검사를 집계 |

일상 개발에서는 `go`로 갱신하고, CI에서는 `go-check` 또는 `go-verify`로 누락을 찾습니다.

## 백엔드는 공개 Go API를 바꾸지 않습니다

동일한 binding 선언에서 native symbol에 도달하는 방법만 선택합니다.

| `link` | 방식 |
|---|---|
| `.cgo_static` | cgo가 정적 archive를 링크하는 기본값 |
| `.cgo_dynamic` | cgo가 공유 library를 링크 |
| `.purego` | cgo 없이 실행 시 공유 library symbol을 로드 |

백엔드를 바꿔도 public package의 API는 가능한 한 같습니다. 달라지는 것은 필요한 native
artifact, 로딩 시점과 배포 방식입니다.

## 어디에서 다음 내용을 찾나요?

- 첫 프로젝트 연결: [시작 가이드](getting-started.md)
- 선언 문법: [바인딩 작성](authoring/README.md)
- 실행 가능한 기능 예제: [예제](examples.md)
- 생성과 배포: [빌드와 배포](build-and-ship/README.md)
- 세부 ABI 검토: [내부 ABI](internals/abi.md)
