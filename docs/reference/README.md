# 참조 문서

정확한 옵션, 타입 지원 조건과 생성 API를 확인할 때 사용합니다.
처음 바인딩을 만든다면 [시작 가이드](../getting-started.md)를 먼저 따라가세요.

| 확인할 내용 | 참조 | 함께 읽을 가이드 |
|---|---|---|
| `addGoBindings`, 설치 경로, 표준 빌드 단계 | [빌드 옵션](build-options.md) | [설정과 백엔드](../build-and-ship/configuration-and-backends.md) |
| `define`, `scope`, 선언과 매개변수 옵션 | [바인딩 API](binding-api.md) | [바인딩 작성](../authoring/README.md) |
| Zig 타입별 Go 표현과 허용 위치 | [타입 대응](type-mapping.md) | [값과 데이터](../authoring/values-and-data.md) |
| 이름, 반환값, 오류, 핸들과 로더 | [생성 Go API](generated-go-api.md) | [객체와 수명](../authoring/objects-and-lifetimes.md) |
| 도구 버전, 플랫폼과 실행 제약 | [지원 범위](support-matrix.md) | [패키징과 배포](../build-and-ship/packaging-and-distribution.md) |
| `ZIGO...` 코드와 해결 방향 | [진단](diagnostics.md) | [문제 해결](../troubleshooting.md) |

확장 개발자를 위한 [플러그인 API](../plugins/api-reference.md)는 별도 참조입니다.
현재 프로젝트에 적용된 이름과 수명 계약은 `zig build go-report`로 확인합니다.

[문서 홈](../README.md)
