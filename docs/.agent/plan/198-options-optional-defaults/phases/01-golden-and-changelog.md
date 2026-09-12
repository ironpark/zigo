---
completed_at: "2026-09-12T18:10:43Z"
depends_on:
- "198-options-optional-defaults#0"
perf_phase: false
status: done
---
> DONE-WHEN: `zig build test`가 갱신된 골든과 함께 통과한다.
> NEXT: none

# 골든과 기록

## Planned Work

- `tests/generator_cases/options_required_fields`에 optional·null 아닌 기본값 필드를
  더합니다. 정수와 bool 두 개를 넣어 값 spelling이 타입마다 맞는지 한 케이스에서 봅니다.
  기존의 `= null` optional 필드는 그대로 두어 세 모양이 나란히 남게 합니다.
- `scripts/update-generator-cases.sh options_required_fields`로 골든을 갱신하고 diff를
  검토합니다. 생성된 Go가 실제로 컴파일되는지 `go vet`이나 임시 모듈 빌드로 확인합니다.
- `CHANGELOG.md`의 `Unreleased`에 수정 항목을 적습니다.

## Done When

- `zig build test`가 갱신된 골든과 함께 통과한다.
- 골든의 생성 Go가 컴파일된다.
- `CHANGELOG.md`에 항목이 있다.
