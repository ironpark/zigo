# GOALS

## Problem and the end result from the user's point of view

현재 생성기와 build graph는 개별 회귀 테스트를 갖추고 있지만, 여러 기능이 동시에
작동할 때의 실패 양상과 실제 CI 경로를 적대적 입력으로 검증한 하나의 감사 결과는 없다.
사용자는 정상·변형·실패·동시성 실험을 통해 현재 기능과 구조의 결함 여부를 재현 가능한
근거와 함께 확인할 수 있어야 한다.

## Measurable goals

- 루트 테스트, 전체 예제, 교차 타깃 compile gate를 깨끗한 상태에서 통과시킨다.
- 동일 입력 반복 생성, 생성물 손상, ABI 호환/비호환 변경, invalid semantic/lock 및 OOM
  실패를 독립 실험으로 검증한다.
- CamelCase, raw 배치, gofmt 유무, 자동 discovery, 대형 API를 실제 build graph에서 검증한다.
- retained callback과 opt-in runtime cleanup을 반복 및 race detector로 검증한다.
- 발견 사항, 재현 명령, 한계와 결론을 저장소 문서에 기록하고 실제 결함에는 회귀 테스트를 둔다.

## Supported scope and non-goals

대상은 현재 저장소의 Zig generator/reflection/build wiring과 생성된 Go API다. 외부 플랫폼의
실기기 실행, 성능 벤치마크, 공개 API 재설계는 범위 밖이다. 교차 타깃은 compile-time
검증으로 제한하며, 결함 수정은 실험에서 재현된 현재 계약 위반에 한한다.

## Reference source / commit / license

현재 브랜치 HEAD와 저장소 내 examples 및 generator golden fixture를 기준으로 한다. 외부
코드를 복사하지 않으며 프로젝트의 기존 라이선스를 따른다.

## Completion criteria for the whole plan

모든 실험군의 명령·기대·관측 결과가 문서화되고, 발견된 결함이 회귀 테스트와 함께 수정되거나
명확한 잔여 위험으로 기록되며, 전체 검증 매트릭스가 통과한다.
