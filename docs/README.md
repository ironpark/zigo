# zigo 사용자 문서

이 문서는 Zig 라이브러리를 Go에서 사용하도록 바인딩을 만들고 배포하는 사람을 위한
문서 홈입니다. 처음이라면 아래 순서만 따라가면 됩니다.

1. [시작 가이드](getting-started.md)에서 첫 바인딩을 생성합니다.
2. [zigo의 작동 방식](how-zigo-works.md)에서 생성 계층과 역할을 확인합니다.
3. [예제](examples.md)에서 자신의 API와 가장 가까운 프로젝트를 찾습니다.
4. 필요한 작업 가이드나 참조 문서만 골라 읽습니다.

## 바인딩 작성

| 하고 싶은 일 | 문서 |
|---|---|
| 공개 함수 선택, 이름 변경과 Go 패키지 구성 | [함수와 패키지](authoring/functions-and-packages.md) |
| scalar, enum, struct와 중첩 결과 노출 | [값과 데이터](authoring/values-and-data.md) |
| 객체 생성, 메서드, borrowed 관계와 `Close` 설계 | [객체와 수명](authoring/objects-and-lifetimes.md) |
| Go callback과 오류·panic 처리 | [콜백과 오류](authoring/callbacks-and-errors.md) |
| `io.Reader`, `io.Writer`와 취소 연결 | [스트림과 취소](authoring/streams-and-cancellation.md) |
| tagged union을 Go 값으로 표현 | [Tagged union](authoring/tagged-unions.md) |

바인딩 선언의 전체 형태와 기능 선택은 [바인딩 작성](authoring/README.md)에서 시작하세요.

## 빌드와 배포

| 하고 싶은 일 | 문서 |
|---|---|
| cgo·purego 백엔드와 빌드 옵션 선택 | [빌드 설정](configuration.md) |
| 생성 파일 갱신, 검사와 CI 구성 | [생성물과 CI](generated-code.md) |
| 공유 라이브러리 로딩과 배포 | [purego](purego.md) |
| 플랫폼, 타입과 수명 제약 확인 | [지원 범위](limitations.md) |
| 생성 실패 원인과 해결 방법 찾기 | [진단](diagnostics.md) |

## 확장과 내부 계약

생성되는 Go API를 확장하려면 [plugin 문서](plugins.md)를 참고하세요. ABI나 생성기 출력
자체를 검토할 때만 [생성 ABI](generated-abi.md), [materialized 결과 ABI](abi.md)와
[생성 runtime](generated-runtime.md)을 읽으면 됩니다.

이 영역은 이후 `docs/plugins/`와 `docs/internals/`로 분리됩니다. 사용자 성공 경로에는
내부 계약을 전제로 하지 않습니다.

## 문서 규칙

- 시작 가이드는 기본 cgo 정적 링크 경로만 설명합니다.
- 작업 가이드는 Zig 입력, binding 선언, 생성되는 Go API와 Go 호출을 함께 보여줍니다.
- 옵션, 타입 대응, 진단과 지원 여부는 각 참조 문서가 정본입니다.
- `...`가 있는 선언 조각은 기존 `zigo.define` 안에 넣는 예시이며 독립 실행 파일이 아닙니다.
- 완전한 실행 코드는 `examples/`와 각 예제의 테스트에서 확인합니다.

zigo 자체를 수정하려면 사용자 문서가 아니라 [기여 안내](../CONTRIBUTING.md)를 사용하세요.
