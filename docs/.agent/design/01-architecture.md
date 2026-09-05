# 아키텍처

zigo는 Zig 모듈과 `bindings.zig`를 입력받아 C ABI shim, Go 패키지와 메타데이터를 생성합니다.
사용자가 설정하는 공개 API는 [빌드 설정](../../configuration.md), 생성 파일의 관리 방법은
[생성물과 CI 관리](../../generated-code.md)를 참고하세요.

## 생성 파이프라인

```text
Zig 모듈 + bindings.zig
        ↓ 호스트 reflector
semantic.json
        ↓ 검증과 lowering + errors.lock.json
abi.Program
        ↓ emitters
Zig shim · C header · Go raw/public · 보고서
        ↓ 타깃 Zig 컴파일
정적 또는 공유 라이브러리
```

reflector는 타입·함수·주석과 바인딩 메타데이터를 수집합니다. generator는 이를 검증하고
공통 ABI IR로 낮춥니다. 각 emitter는 같은 결정을 읽어 파일을 출력합니다. 예를 들어
slice를 포인터와 길이로 분해하는 규칙을 헤더, shim, Go 출력에서 따로 결정하면 안 됩니다.

타깃 라이브러리 컴파일과 호스트에서의 코드 생성은 분리되어 있습니다. 덕분에 크로스
컴파일할 수 있지만, 생성 shim의 타깃 레이아웃 검사와 타깃에서의 실행 테스트가 필요합니다.

## 빌드 그래프와 생성물 게시

`addGoBindings`가 생성·컴파일·검사 스텝을 연결하고 `GoBindings`를 반환합니다.
`addStandardSteps`는 그 스텝에 사용자가 실행할 이름을 붙입니다.

| 스텝 | 역할 |
|---|---|
| `go` | 생성된 파일을 Go 디렉터리에 반영하고 native 아티팩트를 설치 |
| `go-check` | 생성 결과와 기존 파일의 차이를 검사 |
| `go-lib` | native 라이브러리와 헤더 설치 |
| `go-report` / `go-coverage` | 바인딩 내용과 공개 선언의 포함 범위 확인 |
| `abi-check` | 설정된 기준 API와 호환성 비교 |
| `go-doctor` / `go-verify` | 환경 진단과 통합 검증 |

표는 기본 이름입니다. `name_prefix`를 지정하면 이름이 달라집니다. 정확한 의존 관계와
CI에서의 실행 순서는 [생성물과 CI 관리](../../generated-code.md)를 따릅니다.

게시 단계는 생성 표시가 있는 오래된 Go 파일을 정리하지만 사용자가 작성한 파일은 보존합니다.
cgo static의 로컬 링크 입력처럼 환경별 파일은 커밋 대상인 결정적 생성물과 따로 취급합니다.

## 두 호출 백엔드

`.link = .cgo_static`과 `.cgo_dynamic`은 cgo raw 계층을 사용합니다.
`.link = .purego`는 Go에서 공유 라이브러리의 심볼을 로드합니다. 공개 함수·타입의 사용법은
공통이지만 purego에는 로딩 정책과 추가 의존성이 있습니다.

purego 콜백은 native dispatcher와 정수 토큰을 사용하므로 공유 라이브러리가 Go의
`//export` 심볼에 의존하지 않습니다. 버전이 붙은 callback 진입점은 오래된 native
라이브러리와 새 Go 코드의 잘못된 결합을 로딩 단계에서 감지하게 합니다.

## 수명 결정은 lowering에 모은다

ABI IR은 결과의 소유권, release 함수, handle의 destructor와 owner 관계, 매개변수의
retention을 기록합니다. Go·shim emitter는 이 정보를 사용해 복사, 해제, 호출 보호와
콜백 토큰 관리를 생성합니다.

새 기능이 기존 수명 경로를 사용한다면 먼저 ABI IR로 표현하고 해당 경로를 재사용하세요.
출력 파일마다 별도의 소유권 추론을 추가하지 않습니다.
자료구조는 [IR 명세](02-ir-spec.md), 사용자 계약은
[객체 수명](../../bindings-handles.md)에 있습니다.

## 구현 위치

| 관심사 | 소스 |
|---|---|
| 공개 빌드 API | [build.zig](../../../build.zig) |
| 모듈·스텝·테스트 배선 | [build/](../../../build/) |
| 의미 IR·ABI IR·오류 코드 | [src/gen/ir/](../../../src/gen/ir/) |
| 생성기 진입점 | [generator.zig](../../../src/gen/generator.zig) |
| 공통 하강 결정 | [lower.zig](../../../src/gen/lower.zig) |
| 선언 검증과 진단 순서 | [validate/](../../../src/gen/validate/) |
| 출력 파일별 emitter | [emit/](../../../src/gen/emit/) |

변경 검증 방법은 [프로젝트 개발](../../development.md)을 참고하세요.
