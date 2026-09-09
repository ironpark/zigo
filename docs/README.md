# zigo 사용자 문서

Zig 라이브러리를 Go에서 사용할 수 있도록 바인딩을 작성하고 검증·배포하는 개발자를 위한
문서입니다. 처음에는 기본 cgo 정적 링크로 첫 호출을 완성한 뒤 필요한 기능을 추가하세요.

## 시작하기

1. [시작 가이드](getting-started.md) — 빈 프로젝트에서 바인딩 생성과 Go 테스트까지
2. [작동 방식](how-zigo-works.md) — Zig 구현, 바인딩 선언과 생성 패키지의 관계
3. [예제 선택](examples.md) — 자신의 API와 가까운 실행 가능한 프로젝트

## 바인딩 작성

[작성 가이드](authoring/README.md)에서 선언 구조와 타입 표현을 선택합니다.

| 하고 싶은 일 | 문서 |
|---|---|
| 함수 선택, 이름 변경과 Go 하위 패키지 구성 | [함수와 패키지](authoring/functions-and-packages.md) |
| 숫자, 문자열, 구조체와 중첩 결과 전달 | [값과 데이터](authoring/values-and-data.md) |
| 객체 생성, 대여와 `Close` 설계 | [객체와 수명](authoring/objects-and-lifetimes.md) |
| Go 콜백 전달과 오류 처리 | [콜백과 오류](authoring/callbacks-and-errors.md) |
| `io.Reader`, `io.Writer`와 `context.Context` 연결 | [스트림과 취소](authoring/streams-and-cancellation.md) |
| 태그에 따라 달라지는 데이터 표현 | [Tagged union](authoring/tagged-unions.md) |

## 빌드와 배포

| 하고 싶은 일 | 문서 |
|---|---|
| cgo·purego 선택과 경로 설정 | [설정과 백엔드](build-and-ship/configuration-and-backends.md) |
| 생성물 커밋, 변경 검사와 CI 구성 | [생성물과 CI](build-and-ship/generated-files-and-ci.md) |
| Go 모듈과 네이티브 라이브러리 전달 | [패키징과 배포](build-and-ship/packaging-and-distribution.md) |

## 문제 해결과 참조

생성·링크·로드에 실패했다면 [문제 해결](troubleshooting.md)에서 증상에 맞는 확인 순서를
찾으세요. 선언이 유효하지만 결과가 예상과 다르다면 `zig build go-report`를 확인합니다.

[참조 문서](reference/README.md)는 바인딩 API, 빌드 옵션, 타입 대응, 생성 Go API,
지원 조건과 진단 코드의 정확한 계약을 설명합니다.

## 플러그인

생성 Go API에 반복적인 기능을 추가하려면 [플러그인 사용](plugins/README.md)을,
직접 확장을 구현하려면 [플러그인 작성](plugins/authoring.md)을 읽으세요.
한 패키지에서만 필요한 편의 함수는 생성 패키지에 사용자 `.go` 파일로 추가할 수 있습니다.

## 문서 읽는 방법

- 명령은 별도 표시가 없으면 대상 프로젝트의 `build.zig`가 있는 디렉터리에서 실행합니다.
- 작업 가이드의 선언 조각은 [최소 바인딩 구조](authoring/README.md)에 추가합니다.
  `...` 또는 본문 생략 주석이 있는 코드는 단독 실행 파일이 아닙니다.
- Go 호출 조각은 함수 본문에 넣고, 예제에 지정된 패키지를 import합니다.
- 지원 조건과 기본값은 참조 문서에서, 완전한 코드는 연결된 예제에서 확인합니다.

생성된 Go 패키지만 사용하는 개발자는 [생성 Go API](reference/generated-go-api.md)와
[배포 안내](build-and-ship/packaging-and-distribution.md)를 먼저 확인하세요.
zigo 자체에 기여하려면 [기여 안내](../CONTRIBUTING.md), 생성 ABI와 런타임을 검토하려면
[내부 구조](internals/README.md)를 읽으세요.
