---
perf_phase: false
status: in-progress
---
> DONE-WHEN: 위 네 fixture 테스트가 기대한 doc을 반환한다.
> NEXT: none

# doc 수집 규칙: 그룹 주석과 연속 선언 공유

## Planned Work

- `names.zig` `docCommentAlloc` 확장: `///` 없으면 fn 첫 토큰 직전의 원본 바이트에서 빈 줄 없이 붙은 `//` 줄들을 읽는다(`////`·`//!`는 제외).
- 연속 선언 공유: 같은 컨테이너에서 직전 `pub fn`과 빈 줄 없이 연속이고 자기 doc이 없으면 직전 doc을 물려받는다.
- 단위 테스트 fixture(`names.zig` 테스트): `///` 단독, `//` 그룹, 연속 3개 중 첫 번째만 doc, 빈 줄로 끊긴 경우.

## Done When

- 위 네 fixture 테스트가 기대한 doc을 반환한다.
- 기존 예제 생성물에서 의도 밖 doc 변화가 없거나, 있다면 모두 개선인지 검토해 골든에 반영.
