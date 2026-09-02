---
description: 다른 handle의 메서드인 생성자 허용, 정적 백엔드의 링크 입력 수집과 extra_ldflags, 기본 install에 바인딩 라이브러리 포함
plan_status: in-progress
registered_at: "2026-09-02T13:45:42Z"
---
> NEXT: `addStandardSteps`가 기본 install 스텝에 바인딩 라이브러리 설치를 건다. ([Phase 0](phases/00-install-by-default.md))

# Phases

- [x] [Phase 00: 기본 install에 바인딩 라이브러리](phases/00-install-by-default.md)
- [x] [Phase 01: extra_ldflags와 정적 링크 입력 수집](phases/01-static-link-inputs.md)
- [x] [Phase 02: receiver를 가진 생성자](phases/02-method-constructors.md)
- [ ] [Phase 03: 문서와 CHANGELOG](phases/03-docs.md)
- [ ] [Phase 04: doctor의 미해결 심볼 진단](phases/04-doctor-undefined-symbols.md)

# Shared Verification

- `zig build test --summary all`, `zig fmt --check build.zig src tests examples`.
- 전 예제: `zig build --build-file examples/NN/build.zig test go-check abi-check`, `go/`에서 `go vet ./...`·`go test -count=1 ./...`; purego 04/07/08/11 `purego-go`+`purego-go-check`, 10 `-Dpurego=true`.
- 골든 갱신은 실패 출력의 actual 경로로 `zig build snapshot -- <expected> <actual> --update-snapshots`.

# Decisions That Constrain Ordering

0, 1, 2는 독립. 3은 마지막. 4는 조건부. 권장: 0 → 1 → 2 → 3.

# Next Implementation Target

`addStandardSteps`가 기본 install 스텝에 바인딩 라이브러리 설치를 건다.
