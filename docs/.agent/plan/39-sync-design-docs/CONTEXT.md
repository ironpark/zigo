# SCOPE

docs/.agent/design/00-constraints.md, 01-architecture.md, 02-ir-spec.md,
03-lowering-rules.md, 04-implementation-plan.md, README.md.

# CONTEXT

## Current implementation and bottlenecks

purego 백엔드, 동적 링크, tagged union accessor, report/doctor 스텝, addStandardSteps,
source_root/go_package/gofmt/library_loading 옵션이 구현되어 있으나 설계 문서는 이들을
v2 또는 비범위로 서술한다. layout.json 은 구조체 항목이 빈 스텁이다.

## Target structure and invariants

- 05-implementation-status.md 가 구현 대비 차이의 단일 기록이다.
- 설계 문서 본문은 현재 동작을 서술하고, 미구현 항목은 미구현이라고 표시한다.
