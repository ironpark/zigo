---
depends_on:
- go-functional-options
description: 옵션 생성자의 위치 인자 혼합을 정본 관용구로 확정하고, 기본 접두사와 혼합 시그니처를 골든·예제로 검증한다
plan_status: in-progress
registered_at: "2026-09-12T05:02:27Z"
---
> NEXT: phase 0(`mixed-signature-idiom`)부터 시작합니다: `ZIGO061` hint를 실행 가능한 해법으로 ([Phase 0](phases/00-mixed-signature-idiom.md))

# Phases

- [ ] [Phase 00: 혼합 시그니처 관용구와 hint 정정](phases/00-mixed-signature-idiom.md)
- [ ] [Phase 01: 기본 접두사와 혼합 시그니처 골든](phases/01-default-prefix-golden.md)

# Shared Verification

- `zig build test` -- 단위 테스트, 진단 스냅샷, 모든 generator case 골든 비교.
- `zig build test -Dtest-filter=<case>` -- 새 골든 케이스만 좁혀 확인.
- `scripts/update-generator-cases.sh <case>` -- 골든 재생성 후 diff 검토.
- `cd examples/07-event-queue && zig build go-check abi-check` -- 예제 생성과 ABI 불변 확인.
- `cd examples/07-event-queue/go && go test -count=1 ./...`, `go-purego`는 `CGO_ENABLED=0`으로
  같은 명령 -- 혼합 시그니처의 실제 호출과 기본값 적용 확인.
- 문서 링크·anchor 검사와 `gofmt`/`zig fmt --check`.

# Decisions That Constrain Ordering

두 phase는 서로 독립이지만 둘 다 `192-go-functional-options`가 끝난 뒤에만 의미가 있습니다.
phase 0은 진단·문서·예제를, phase 1은 골든을 맡고 파일이 겹치지 않아 순서를 바꿔도 됩니다.

# Next Implementation Target

phase 0(`mixed-signature-idiom`)부터 시작합니다: `ZIGO061` hint를 실행 가능한 해법으로
