# GOALS

## Problem and the end result from the user's point of view

현재 문서는 기능 설명은 충실하지만 빠른 시작, 설정 참조, 생성물 운영, 고급 백엔드 설명이
긴 문서에 섞여 있다. 처음 온 사용자가 기본 cgo 경로를 성공시키고, 이후 자신의 목적에 맞는
문서로 이동할 수 있도록 README와 사용자 문서를 작업 흐름 중심으로 재구성한다.

## Measurable goals

- README만 읽어도 지원 환경, 기본 사용 경로, 최소 생성·테스트 명령을 파악할 수 있다.
- 문서 인덱스가 시작, 바인딩 설계, 생성물 운영, purego 배포, 문제 해결의 목적별 경로를 제공한다.
- 400줄이 넘는 설정 문서를 설정, 바인딩 선언, 생성물 관리의 독립된 참조 문서로 나눈다.
- 모든 Markdown 상대 링크와 문서에 제시된 주요 Zig/Go 명령을 검증한다.

## Supported scope and non-goals

README, `docs/*.md`, 필요한 새 사용자 문서와 사용자 문서에서 직접 연결하는 예제 안내가 범위다.
내부 `.agent/design` 문서, 라이브러리 구현, 생성 API와 예제 코드는 변경하지 않는다. 공개 동작을
새로 약속하지 않고 현재 구현과 테스트가 보장하는 범위만 설명한다.

## Reference source / commit / license

현재 작업 트리의 `build.zig`, `src/build_options.zig`, `examples/`, `.github/workflows/ci.yml`을
정본으로 삼는다. 프로젝트 라이선스는 루트 `LICENSE`의 MIT 조건을 유지한다.

## Completion criteria for the whole plan

사용자 문서의 정보 구조가 목적별로 분리되고, 중복 설명에는 정본 링크가 있으며, 로컬 상대 링크가
모두 존재한다. 문서의 기본 생성·검사 명령이 실제 예제에서 성공하고 작업 트리가 계획 상태와 함께
커밋되어 있다.
