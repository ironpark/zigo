# zigo 사용자 문서

처음 사용한다면 아래 세 문서를 순서대로 읽는 것이 가장 빠릅니다.

1. [시작 가이드](getting-started.md)에서 기본 cgo 바인딩을 생성하고 테스트합니다.
2. [예제 선택 가이드](examples.md)에서 자신의 API와 가장 비슷한 예제를 찾습니다.
3. [`bindings.zig` 선언](bindings.md)에서 필요한 타입과 함수 메타데이터를 확인합니다.

설치 전에 완성된 프로젝트를 실행해 보고 싶다면
[최소 실행 예제](../examples/00-quick-start/README.md)에서 시작하세요.

## 목적별로 찾기

| 하고 싶은 일 | 읽을 문서 |
|---|---|
| zigo를 설치하고 첫 Go 바인딩 만들기 | [시작 가이드](getting-started.md) |
| 백엔드, Go 패키지와 빌드 옵션 선택하기 | [빌드 설정](configuration.md) |
| 함수·타입·콜백을 어떻게 선언하는지 확인하기 | [`bindings.zig` 선언](bindings.md) |
| 생성 파일, 빌드 스텝과 CI 정책 확인하기 | [생성물과 CI 관리](generated-code.md) |
| 실행 가능한 코드에서 기능 찾기 | [예제 선택 가이드](examples.md) |
| `CGO_ENABLED=0`으로 빌드하거나 공유 라이브러리 배포하기 | [공유 라이브러리와 purego](purego.md) |
| 지원하지 않는 타입, ABI 또는 수명 제약 확인하기 | [지원 범위와 제한사항](limitations.md) |
| materialized 결과 버퍼의 바이너리 형식 확인하기 | [Materialized 버퍼 ABI](abi.md) |
| zigo 저장소를 빌드하고 변경 검증하기 | [프로젝트 개발](development.md) |

## 바인딩 상세 가이드

[`bindings.zig` 선언](bindings.md)에서 기본 구조를 확인한 뒤 필요한 주제만 읽으세요.

| 주제 | 문서 |
|---|---|
| 함수 선택·이름·자동 발견·하위 패키지 | [함수와 패키지](bindings-functions.md) |
| 정수·enum·struct·atomic·중첩 결과 | [값 타입과 결과 트리](bindings-types.md) |
| 생성자·Close·borrowed·부모와 자식·인터페이스 | [객체 수명](bindings-handles.md) |
| 문자열·slice·출력 버퍼·optional | [문자열과 버퍼](bindings-buffers.md) |
| 콜백·Go 오류·panic | [콜백과 오류 처리](bindings-callbacks.md) |
| io.Writer·io.Reader·context.Context | [스트림과 취소](bindings-streams.md) |
| projection·Variant·snapshot·값 전달 | [Tagged union](bindings-unions.md) |

생성 오류는 [진단 코드](diagnostics.md)로 찾을 수 있습니다. C 헤더나 생성기 자체를 검토할
때는 [생성 ABI와 메타데이터](generated-abi.md), [생성 Go 코드의 내부 구조](generated-runtime.md)를
참고하세요.

## 기본 경로와 선택 기능

기본 사용 경로는 `.cgo_static`입니다. Zig, Go와 C 컴파일러가 준비된 네이티브 환경에서
먼저 이 경로로 동작을 확인하세요. `.cgo_dynamic`, `.purego`, 자동 API 발견과 ABI 검사는
필요가 분명할 때 추가하는 선택 기능입니다.

프로젝트 내부 구조와 구현 근거는 사용자 문서가 아니라
[설계 문서](.agent/design/README.md)에 정리되어 있습니다.

## 문서의 용어와 코드 읽기

| 용어 | 이 문서에서의 의미 |
|---|---|
| native | Go에서 호출하는 Zig 코드와 그 라이브러리 |
| handle | native 객체를 가리키며 사용 가능 상태·수명을 관리하는 Go 객체 |
| caller-owned | 호출자에게 소유권을 넘긴 결과; handle은 `Close`, 버퍼는 생성 코드가 해제 |
| borrowed | 원래 소유자에게서 빌린 값; 소유자의 수명 계약을 따라야 함 |
| raw | C ABI 호출·변환을 담당하는 생성 계층; 보통 직접 import하지 않음 |
| ABI | 두 언어가 공유하는 함수 호출·데이터 표현 계약 |

시작 가이드에는 저장할 파일과 실행할 명령을 함께 제시합니다. 상세 가이드의
`.types = ...`·`.functions = ...`는 기존 `zigo.define`에 넣는 부분 선언이며,
`...`나 생략 주석이 있는 코드는 그대로 실행하는 예제가 아닙니다.
“생성되는 API”는 시그니처 설명, “사용 예제”는 호출 코드로 구분합니다.
완성된 실행 코드는 각 예제의 `example_test.go`를 참고하세요.
