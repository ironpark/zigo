---
completed_at: "2026-08-31T17:41:23Z"
depends_on:
- "44-user-friendly-documentation#0"
perf_phase: false
status: done
---
> DONE-WHEN: 설정, 바인딩 선언, 생성물 운영이 각각 독립적으로 탐색 가능한 정본 문서가 된다.
> NEXT: none

# Reference split and consistency audit

## Planned Work

- 비대한 설정 문서에서 `bindings.zig` 선언과 생성물·CI 운영을 각각 새 참조 문서로 분리한다.
- 설정 문서는 옵션 선택과 링크·패키지 구성에 집중하도록 목차와 설명을 다듬는다.
- purego, 제한사항과 새 참조 문서 사이의 중복을 줄이고 현재 API와 맞지 않는 표현을 바로잡는다.
- 전체 문서의 상대 링크, 제목 앵커, 지원 버전, 빌드 스텝 이름과 코드 식별자를 구현·예제와 대조한다.

## Done When

- 설정, 바인딩 선언, 생성물 운영이 각각 독립적으로 탐색 가능한 정본 문서가 된다.
- 모든 사용자 문서의 상대 링크가 유효하고, 문서의 핵심 검증 명령이 성공하며, 오래된 공개 API 표현이 없다.
