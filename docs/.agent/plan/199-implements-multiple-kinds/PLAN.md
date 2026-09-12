---
description: 한 메서드가 여러 Go 표준 인터페이스를 구현하도록 .implements가 kind 목록을 받게 한다
plan_status: in-progress
registered_at: "2026-09-12T18:13:45Z"
---
> NEXT: phase 0(`kind-list-contract`)부터 시작합니다: 선언에서 semantic까지 kind를 목록으로 옮깁니다. ([Phase 0](phases/00-kind-list-contract.md))

# Phases

- [ ] [Phase 00: kind 목록 계약](phases/00-kind-list-contract.md)
- [ ] [Phase 01: 여러 래퍼 방출과 이름 검사](phases/01-emit-and-names.md)
- [ ] [Phase 02: 예제와 문서](phases/02-example-and-docs.md)

# Shared Verification

- `zig build test --summary all`.
- `scripts/update-generator-cases.sh implements_std implements_std_purego` 후 `git diff`.
- `cd examples/11-io-streams && zig build test go-check go-lib abi-check go-coverage --summary all`.
- `cd examples/11-io-streams/go && go test -count=1 ./...`, purego는 `CGO_ENABLED=0`.
- `zig fmt --check`, 문서 링크·anchor 검사.

# Decisions That Constrain Ordering

phase 0이 목록을 계약으로 만들고, phase 1이 그것을 읽어 여러 래퍼를 내고, phase 2가 예제와
문서로 고정합니다.

# Next Implementation Target

phase 0(`kind-list-contract`)부터 시작합니다: 선언에서 semantic까지 kind를 목록으로 옮깁니다.
