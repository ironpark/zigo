---
completed_at: "2026-09-02T05:26:51Z"
depends_on:
- "65-metadata-and-godoc-fidelity#1"
perf_phase: false
status: done
---
> DONE-WHEN: 모든 예제·골든의 공개·raw 패키지에 패키지 doc이 정확히 하나씩 있고 godoc_audit이 단정한다.
> NEXT: none

# 패키지 doc 생성

## Planned Work

- `Options.go_package_doc` 추가, `build.zig` `addGoBindings`에 plumbing, `bindings.zig` 최상위 `//!` doc을 `names.zig`에서 수집해 fallback으로 사용. 마지막 fallback은 기본 문장.
- 공개 패키지 메인 파일과 raw 패키지 한 파일에만 `// Package {name} …` 출력. 여러 줄 doc은 `//` 줄로 이어 쓴다.
- `godoc_audit`: 패키지마다 정확히 한 파일이 `file.Doc`을 가지며 `Package {name}`으로 시작함을 단정.
- 예제 하나(예: 07-event-queue)에 옵션 사용 예를, 다른 하나에 `//!` fallback 예를 둔다.
- `docs/bindings.md` 옵션 표와 doc 주석 규칙 절 갱신.

## Done When

- 모든 예제·골든의 공개·raw 패키지에 패키지 doc이 정확히 하나씩 있고 godoc_audit이 단정한다.
- `zig build test`, 예제 10개 `go-check`·`go vet`·`go test` 통과.
