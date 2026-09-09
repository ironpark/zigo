# 생성 계약과 내부 구조

이 영역은 생성된 C ABI와 Go runtime을 검토하거나 zigo 구현을 수정하는 사람을 위한
문서입니다. 일반 사용자는 [바인딩 작성](../authoring/README.md)과
[빌드와 배포](../build-and-ship/README.md)만 읽으면 됩니다.

- [ABI](abi.md) — 함수, 상태 코드, ownership과 metadata 계약
- [Materialized 형식](materialized-format.md) — 중첩 결과 buffer의 binary layout
- [생성 Go runtime](generated-runtime.md) — 파일 역할, handle과 callback runtime

이 문서는 public Go API보다 낮은 계층을 설명합니다. raw package와 metadata schema는 zigo
release 사이에서 바뀔 수 있으며, compatibility가 필요한 C ABI는 `abi-check`로 명시적으로
관리합니다.
