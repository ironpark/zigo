---
description: 공개 Go 패키지를 go_dir 루트(모듈 루트)에 발행할 수 있도록 패키지 경로와 이름을 분리
plan_status: in-progress
registered_at: "2026-09-02T13:52:31Z"
---
> NEXT: `go_package_path` 옵션을 추가하고 공개 패키지 출력 경로와 import path를 이름이 아닌 경로에서 계산한다. ([Phase 0](phases/00-package-path-option.md))

# Phases

- [x] [Phase 00: 패키지 경로 옵션과 생성 경로](phases/00-package-path-option.md)
- [ ] [Phase 01: 루트 발행 예제](phases/01-root-package-example.md)
- [ ] [Phase 02: 문서와 CHANGELOG](phases/02-docs.md)

# Shared Verification

- `zig build test --summary all`, `zig fmt --check build.zig src tests examples`.
- 전 예제: `zig build --build-file examples/NN/build.zig test go-check abi-check`, `go/`(또는 루트 발행 예제는 go.mod 위치)에서 `go vet ./...`·`go test -count=1 ./...`; purego 04/07/08/11 `purego-go`+`purego-go-check`, 10 `-Dpurego=true`.
- 골든 갱신은 실패 출력의 actual 경로로 `zig build snapshot -- <expected> <actual> --update-snapshots`.

# Decisions That Constrain Ordering

0 → 1 → 2 순차. 플랜 75와 파일이 겹치므로(`build.zig`, `docs/configuration.md`, CHANGELOG) 75가 끝난 뒤 시작하거나 rebase를 감안한다.

# Next Implementation Target

`go_package_path` 옵션을 추가하고 공개 패키지 출력 경로와 import path를 이름이 아닌 경로에서 계산한다.
