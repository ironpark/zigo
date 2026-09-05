---
depends_on:
- "112-112-explicit-interfaces#2"
perf_phase: false
status: in-progress
---
> DONE-WHEN: `zig build test` 녹색, 예제 05의 생성물과 `semantic.json`이 커밋되어 있다.
> NEXT: none

# Example, abi-diff and docs

## Planned Work

- `examples/05-pipeline/src/bindings.zig`에 `Batch` 인터페이스(`len`, closer)를 등록하고
  `semantic.json`과 `go/`를 재생성한다. 예제 Go 테스트에 `var batches []pipeline.Batch` 사용을 더한다.
- `abi_diff.zig`: 인터페이스 추가 added, 제거 breaking, 메서드 목록·타입 목록·closer 변경 breaking.
  테스트 추가.
- `docs/bindings.md`에 "인터페이스" 절(등록 형태, 검증 규칙, 생성 Go, `anytype`은 Zig wrapper로).
  `docs/limitations.md`의 generic 항목에 인터페이스 등록을 언급한다.
- CHANGELOG `[Unreleased]` `Added`에 기록하고 `semantic.json` 필드 추가로 minor 릴리즈임을 적는다.

## Done When

- `zig build test` 녹색, 예제 05의 생성물과 `semantic.json`이 커밋되어 있다.
- abi-diff 테스트와 문서가 들어 있다.
