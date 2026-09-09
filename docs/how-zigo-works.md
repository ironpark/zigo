# zigo의 작동 방식

zigo는 Zig 구현을 직접 변경하거나 Zig 타입을 그대로 Go 메모리에 노출하지 않습니다.
사용자가 선택한 공개 API를 언어 사이에서 안전하게 전달할 수 있는 계약으로 낮춘 뒤 두 언어의
코드를 함께 생성합니다.

## 입력에서 생성물까지

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
- `build.zig`는 출력 위치, Go 모듈, 백엔드와 설치 정책을 정합니다.
- zigo는 이 입력을 검증한 뒤 Zig shim, C 헤더, Go 코드와 메타데이터를 생성합니다.

## `bindings.zig`는 구현이 아니라 공개 계약입니다

라이브러리 코드는 Go를 알 필요가 없습니다. 다음 선언은 기존 Zig 함수 하나를 선택합니다.

```zig
const api = zigo.scope(library);

pub const bindings = zigo.define(.{
    .root = library,
    .declarations = &.{api.func("add", .{})},
});
```

필요한 경우 함수 이름, 매개변수 의미, 생성자와 소멸자, 콜백 수명이나 결과 표현을
추가로 선언합니다. zigo는 Zig 선언과 바인딩 메타데이터가 모순되면 코드를 만들기 전에
`ZIGO...` 진단으로 거부합니다.

## raw 계층과 공개 계층

생성 Go 모듈에는 역할이 다른 두 계층이 있습니다.

| 계층 | 역할 | 직접 사용 여부 |
|---|---|---|
| raw 패키지 | C ABI 호출, 포인터와 스칼라 변환 | 보통 import하지 않음 |
| 공개 패키지 | Go 이름, error, 핸들, 콜백과 인터페이스 | 애플리케이션이 사용 |

예를 들어 Zig 오류 유니온은 raw 상태 코드로 전달되지만 공개 패키지에서는 Go `error`로
보입니다. opaque 포인터는 공개 패키지에서 동시 호출과 `Close`를 관리하는 핸들이
됩니다.

## 수명은 API의 일부입니다

언어 경계를 넘는 값은 복사 여부와 소유자를 명확히 해야 합니다.

- 스칼라와 작은 값 구조체는 값으로 전달됩니다.
- 입력 문자열과 슬라이스는 호출 동안만 빌립니다.
- caller-owned 결과는 생성 코드가 복사하거나 정해진 해제 함수로 해제합니다.
- opaque 객체는 Go 핸들이 소유하고 `Close`로 해제합니다.
- borrowed 핸들은 부모 객체보다 오래 사용할 수 없습니다.
- retained 콜백은 네이티브 코드가 보관하는 동안 Go registry에 유지됩니다.

세부 계약은 값, 버퍼, 객체와 콜백 가이드에서 기능별로 설명합니다.

## 생성과 검사는 다른 작업입니다

`addStandardSteps`가 등록하는 기본 단계는 의도가 구분되어 있습니다.

| 단계 | 역할 |
|---|---|
| `go` | 생성물을 갱신하고 현재 타깃의 네이티브 라이브러리를 빌드 |
| `go-check` | 커밋한 생성물이 최신인지 검사 |
| `go-lib` | 네이티브 라이브러리와 헤더를 설치 |
| `go-doctor` | Go와 네이티브 도구 모음 전제 검사 |
| `go-report` | 최종 바인딩 결정 설명 |
| `go-coverage` | 공개 Zig 함수의 바인딩 포함 여부 보고 |
| `abi-check` | 설정한 기준과 ABI 호환성 비교 |
| `go-verify` | 검사, 도구 모음, 라이브러리와 선택적 ABI 검사를 집계 |

일상 개발에서는 `go`로 갱신하고, CI에서는 `go-check` 또는 `go-verify`로 누락을 찾습니다.

## 백엔드 선택과 공개 Go API

동일한 바인딩 선언에서 네이티브 심볼에 도달하는 방법만 선택합니다.

| `link` | 방식 |
|---|---|
| `.cgo_static` | cgo가 정적 archive를 링크하는 기본값 |
| `.cgo_dynamic` | cgo가 공유 라이브러리를 링크 |
| `.purego` | cgo 없이 실행 시 공유 라이브러리 심볼을 로드 |

백엔드를 바꿔도 공개 패키지의 API는 가능한 한 같습니다. 달라지는 것은 필요한 네이티브
산출물, 로딩 시점과 배포 방식입니다. purego에는 로더 API가 추가될 수 있으며 콜백 반환
타입에도 제약이 있으므로 [지원 범위](reference/support-matrix.md)를 함께 확인하세요.

## 어디에서 다음 내용을 찾나요?

- 첫 프로젝트 연결: [시작 가이드](getting-started.md)
- 선언 문법: [바인딩 작성](authoring/README.md)
- 실행 가능한 기능 예제: [예제](examples.md)
- 생성과 배포: [빌드와 배포](build-and-ship/README.md)
- 세부 ABI 검토: [내부 ABI](internals/abi.md)
