---
perf_phase: false
status: planned
---
> DONE-WHEN: reflector가 semantic 문서만 산출한다.
> NEXT: none

# Drop the unused layout artifact

## Planned Work

- reflector의 `layout.json` 출력과 그 CLI 인자, `build.zig`의 `_ = layout_json;` 배선을 제거한다.
- `source_root` 부재를 빈 문자열로 표현하던 위치 인자도 함께 정리한다.
- `02-ir-spec.md` §2와 `00-constraints.md` §7에서 이 파일을 삭제하고, 헤더 레이아웃 검증을
  후속 과제로 남긴다.

## Done When

- reflector가 semantic 문서만 산출한다.
- 문서에 소비되지 않는 산출물 서술이 남지 않는다.
