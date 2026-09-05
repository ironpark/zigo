# 구현 상태

이 문서는 현재 기능을 확인할 코드와 예제를 연결합니다. 과거 구현 계획의 체크리스트가
아니며, 사용자용 전체 지원 조건은 [지원 범위와 제한사항](../../limitations.md)에 있습니다.

## 구현된 기능

| 기능 | 확인할 문서·예제 |
|---|---|
| cgo 정적·동적 링크와 purego | [빌드 설정](../../configuration.md), [purego](../../purego.md) |
| 타깃 지정과 크로스 컴파일 | [시작 가이드](../../getting-started.md), [purego](../../purego.md) |
| 함수 명시 등록·자동 발견·하위 패키지 | [함수와 패키지](../../bindings-functions.md), [08-telemetry-hub](../../../examples/08-telemetry-hub/) |
| 값 타입·enum·atomic | [값 타입](../../bindings-types.md), [07-event-queue](../../../examples/07-event-queue/) |
| handle·borrowed·타입 간 참조 | [객체 수명](../../bindings-handles.md), [09-type-relations](../../../examples/09-type-relations/) |
| 콜백·오류·panic 경계 | [콜백](../../bindings-callbacks.md), [04-callback](../../../examples/04-callback/) |
| tagged union | [Tagged union](../../bindings-unions.md), [10-tagged-union](../../../examples/10-tagged-union/) |
| 스트림과 취소 | [스트림](../../bindings-streams.md), [11-io-streams](../../../examples/11-io-streams/) |
| materialized 결과 | [값 타입](../../bindings-types.md), [12-materialized](../../../examples/12-materialized/) |
| 명시 등록 Go 인터페이스 | [객체 수명](../../bindings-handles.md), [interfaces 검증](../../../src/gen/validate/interfaces.zig) |
| ABI 검사·보고서·coverage·doctor | [생성물과 CI 관리](../../generated-code.md) |

지원 플랫폼과 조건은 사용자 문서에 모읍니다. 특히 “Windows 미지원”, “크로스 컴파일
미지원”, 공개 옵션 `backend`·`link_mode`라는 과거 설명은 현재 공개 API에 적용되지 않습니다.
현재 공개 선택지는 `Options.link`입니다. 생성기 내부의 backend 정보와 혼동하지 마세요.

## 자동화하지 않는 영역

- 임의의 Zig generic API를 Go에 자동으로 노출하지 않습니다. 명시적인 wrapper가 필요합니다.
- 소유권 선언이 native 구현과 실제로 일치하는지 증명하지 않습니다.
- 생성물 검사나 ABI diff가 메모리 안전성·스레드 안전성·타깃 실행 테스트를 대신하지 않습니다.
- purego도 OS·아키텍처별 native 라이브러리 빌드와 배포가 필요합니다.

## 검증 기준

[프로젝트 개발](../../development.md)의 명령으로 단위·스냅샷·Go 통합 테스트를 실행합니다.
실제로 실행하는 플랫폼 매트릭스는 [CI](../../../.github/workflows/ci.yml)를 확인하세요.
“코드가 지원하는 타깃”과 “모든 CI 실행에서 검증하는 타깃”은 같은 뜻이 아닙니다.

과거 설계와 도입 당시의 논의는 [설계 문서 목차](README.md)의 기록 섹션에 보존합니다.
