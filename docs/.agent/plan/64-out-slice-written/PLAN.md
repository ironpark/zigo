---
completed_at: "2026-09-02T04:54:42Z"
description: out 슬라이스 왕복 복사 제거, .written 힌트, 스칼라 extern struct 슬라이스 캐스트 경로
plan_status: done
registered_at: "2026-09-02T04:29:27Z"
---
> NEXT: `.written` 메타데이터를 semantic/reflect/validate/abi_diff에 관통시키고 ZIGO017과 compatible 분류 테스트를 만든다. ([Phase 0](phases/00-written-metadata.md))

# Phases

- [x] [Phase 00: `.written` 메타데이터와 진단, abi_diff](phases/00-written-metadata.md)
- [x] [Phase 01: shim의 `written` 기록과 공개 계층의 되돌리기 규칙](phases/01-shim-written.md)
- [x] [Phase 02: Go 쪽 레이아웃 가드와 캐스트 적격 predicate](phases/02-go-layout-guard.md)
- [x] [Phase 03: 캐스트 경로와 out 무복사 진입](phases/03-cast-path.md)
- [x] [Phase 04: 예제 `…Into(dst)` 패턴과 문서](phases/04-example-and-docs.md)

# Shared Verification

- 단위: `zig build test --summary all` (reflect, semantic 직렬화, validate ZIGO017, abi_diff, emit 문자열 단정, generator_cases 골든, 새 부정 컴파일 테스트).
- 예제: `for e in examples/*; do (cd $e && zig build test go-check abi-check --summary all); (cd $e/go && go test -count=1 ./...); done` 와 purego 예제 4개(`04`, `07`, `08`, `10`)의 `go-purego` 테스트.
- 생성물 갱신은 `zig build go` (purego는 `zig build go -Dpurego=true`), 골든은 `zig build snapshot -- <expected> <actual> --update-snapshots` 로 현재 실패 출력이 가리키는 actual 디렉터리를 사용한다. 오래된 `.zig-cache` actual을 잡지 않도록 주의.
- 문서 정확성: 각 문서의 예제 스니펫이 실제 골든과 일치하는지 눈으로 대조.

# Decisions That Constrain Ordering

0 (`written-metadata`)과 2 (`go-layout-guard`)는 독립이라 병행 가능. 1은 0에, 3은 1과 2에 의존한다. 4는 3 뒤. 각 phase 끝에서 `zig build test`가 녹색이어야 다음으로 간다. phase 3은 성능 목적(perf_phase)이므로 골든 변화가 크다 — 별도 커밋으로 남긴다.

# Next Implementation Target

`.written` 메타데이터를 semantic/reflect/validate/abi_diff에 관통시키고 ZIGO017과 compatible 분류 테스트를 만든다.
