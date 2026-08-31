# zigo 사용자 문서

처음 사용한다면 아래 세 문서를 순서대로 읽는 것이 가장 빠릅니다.

1. [시작 가이드](getting-started.md)에서 기본 cgo 바인딩을 생성하고 테스트합니다.
2. [예제 선택 가이드](examples.md)에서 자신의 API와 가장 비슷한 예제를 찾습니다.
3. [설정과 생성물](configuration.md)에서 필요한 옵션과 선언 메타데이터만 확인합니다.

## 목적별로 찾기

| 하고 싶은 일 | 읽을 문서 |
|---|---|
| zigo를 설치하고 첫 Go 바인딩 만들기 | [시작 가이드](getting-started.md) |
| 함수·타입·콜백을 어떻게 선언하는지 확인하기 | [설정과 생성물](configuration.md) |
| 실행 가능한 코드에서 기능 찾기 | [예제 선택 가이드](examples.md) |
| `CGO_ENABLED=0`으로 빌드하거나 공유 라이브러리 배포하기 | [공유 라이브러리와 purego](purego.md) |
| 지원하지 않는 타입, ABI 또는 수명 제약 확인하기 | [지원 범위와 제한사항](limitations.md) |
| zigo 저장소를 빌드하고 변경 검증하기 | [프로젝트 개발](development.md) |

## 기본 경로와 선택 기능

기본 사용 경로는 `.cgo_static`입니다. Zig와 Go가 설치된 네이티브 macOS/Linux 환경에서
먼저 이 경로로 동작을 확인하세요. `.cgo_dynamic`, `.purego`, `auto_cleanup`, 자동 API
발견과 ABI 검사는 필요가 분명할 때 추가하는 선택 기능입니다.

프로젝트 내부 구조와 구현 근거는 사용자 문서가 아니라
[설계 문서](.agent/design/README.md)에 정리되어 있습니다.
