# 빌드와 배포

이 영역은 바인딩 선언이 끝난 뒤 생성물을 만들고 검사하여 다른 환경에 전달하는 작업을
설명합니다.

## 목적별 문서

| 작업 | 문서 |
|---|---|
| cgo static, cgo dynamic 또는 purego 선택 | [설정과 백엔드](configuration-and-backends.md) |
| 생성 파일 갱신, 커밋과 CI 검사 | [생성물과 CI](generated-files-and-ci.md) |
| 네이티브 라이브러리와 Go 모듈 배포 | [패키징과 배포](packaging-and-distribution.md) |

처음에는 `.cgo_static`과 단일 호스트 대상을 사용하세요. 첫 Go 호출이 동작한 뒤에만
multi-target, dynamic linking 또는 purego를 추가하는 것이 문제를 분리하기 쉽습니다.

모든 `addGoBindings` 필드는 [빌드 옵션 참조](../reference/build-options.md), 지원하는
플랫폼은 [지원 범위](../reference/support-matrix.md)가 정본입니다.
