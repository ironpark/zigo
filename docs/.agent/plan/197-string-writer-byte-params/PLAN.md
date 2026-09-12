---
description: 바이트 매개변수에도 .string_writer를 허용하고 복사 없는 WriteString 래퍼를 생성한다
plan_status: in-progress
registered_at: "2026-09-12T07:31:18Z"
---
> NEXT: phase 0(`borrowed-bytes-wrapper`)부터 시작합니다: `ZIGO058`이 string 도달이 아니라 빌려 온 바이트를 묻게 고칩니다. ([Phase 0](phases/00-borrowed-bytes-wrapper.md))

# Phases

- [x] [Phase 00: 바이트 매개변수 허용과 빌려 넘기는 래퍼](phases/00-borrowed-bytes-wrapper.md)
- [ ] [Phase 01: 골든과 예제](phases/01-goldens-and-example.md)
- [ ] [Phase 02: 문서](phases/02-docs.md)

# Shared Verification

- `zig build test --summary all` -- 단위 테스트, 진단 스냅샷, generator case 골든 비교.
- `scripts/update-generator-cases.sh implements_std implements_std_purego` 후 `git diff`.
- `cd examples/11-io-streams && zig build test go-check go-lib abi-check go-coverage --summary all`.
- `cd examples/11-io-streams/go && go test -count=1 ./...`.
- `cd examples/11-io-streams && zig build purego-go purego-go-verify` 후
  `cd go-purego && CGO_ENABLED=0 go test -count=1 ./...`.
- `gofmt -l`, `zig fmt --check`, 문서 링크·anchor 검사.

# Decisions That Constrain Ordering

phase 0이 먼저입니다. 검증이 거절하는 동안에는 골든도 예제도 만들 수 없습니다. phase 1은
그 방출을 고정하고, phase 2는 확정된 동작을 문서에 적습니다.

# Next Implementation Target

phase 0(`borrowed-bytes-wrapper`)부터 시작합니다: `ZIGO058`이 string 도달이 아니라 빌려 온 바이트를 묻게 고칩니다.
