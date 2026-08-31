# GOALS

## Problem and the end result from the user's point of view

docs/.agent/design 는 초기 설계 시점의 서술을 그대로 담고 있어 현재 구현과 어긋난다.
감사 문서가 제거된 뒤 README 링크도 깨졌다. 설계 문서를 읽는 사람이 문서를 현재 구현의
진실로 신뢰할 수 있어야 한다.

## Measurable goals

- 남은 설계 문서 5종과 구현의 차이를 구현 상태 문서 1개로 정리한다.
- 00~04 문서와 README에서 구현과 어긋나는 서술을 실제 동작으로 교정한다.
- 삭제된 문서를 가리키는 링크가 남지 않는다.

## Supported scope and non-goals

- 범위: docs/.agent/design 문서. 사용자 문서(docs/*.md)는 이미 최신이므로 링크 정합성만 확인한다.
- 비범위: 소스 코드 변경, 새 기능 설계.

## Reference source / commit / license

저장소 현재 HEAD (`docs/zig-go-binding-architecture` 브랜치)의 build.zig, src/, examples/.

## Completion criteria for the whole plan

설계 문서가 구현된 것, 설계와 다른 것, 미구현인 것을 명시하고 그 외 서술이 구현과 일치한다.
