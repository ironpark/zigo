# GOALS

## Problem and the end result from the user's point of view

현재 사용자 문서는 온보딩, 작업 가이드, API 참조, 생성기 내부 설명이 평면적으로 섞이고 같은 사실이 여러 문서에 반복된다. 새 사용자는 하나의 기본 경로로 성공하고, 기존 사용자는 목적별 문서와 정본 참조를 곧바로 찾을 수 있는 구조로 전면 교체한다.

## Measurable goals

- README에서 기본 예제 실행과 사용자 문서 홈까지 한 번에 이동할 수 있다.
- 사용자 문서를 시작, 개념, 바인딩 작성, 빌드·배포, 참조, 플러그인, 내부 계약으로 분류한다.
- 모든 마이그레이션 문서를 제거하고 현재 공개 API만 설명한다.
- 플러그인 문서를 `docs/plugins/` 아래의 독립 영역으로 분리한다.
- 문서의 로컬 링크와 대표 명령을 검증한다.

## Supported scope and non-goals

루트 README, `docs/`의 사용자·기여자 문서, 예제와 bundled plugin README를 재작성한다. `docs/.agent/`의 설계·연구·계획 기록과 구현 자체는 변경하지 않는다. 과거 버전용 마이그레이션이나 번역 문서는 만들지 않는다.

## Reference source / commit / license

현재 작업 트리의 공개 Zig API, 빌드 스텝, 테스트, 예제와 MIT 라이선스를 정본으로 사용한다. 기존 사용자 문서는 누락 방지용 목록으로만 참고한다.

## Completion conditions for the whole plan

새 정보 구조의 모든 문서가 현재 구현과 일치하고, 마이그레이션 문서와 그 링크가 없으며, 플러그인 문서가 독립 폴더에 있고, Markdown 링크 및 대표 빌드·테스트 검증이 통과한다.
