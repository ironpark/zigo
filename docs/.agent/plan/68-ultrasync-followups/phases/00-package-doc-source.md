---
completed_at: "2026-09-02T06:38:52Z"
perf_phase: false
status: done
---
> DONE-WHEN: 위 테스트 통과, 01-scalar 생성물이 루트 doc을 담는다.
> NEXT: none

# 패키지 doc fallback을 루트 모듈 `//!`로

## Planned Work

- `names.zig`: `containerDocAlloc`을 `root_source`에 적용, `bindings_source`에는 적용하지 않는다. 루트 파일이 없거나 읽기 실패면 doc 없음.
- 01-scalar: `//!`를 `src/bindings.zig`에서 `src/root.zig`로 옮기고 생성물 갱신. 테스트: 루트 `//!`만 반영되고 bindings `//!`는 무시.
- `docs/bindings.md` 패키지 doc 절, `docs/configuration.md` 옵션 표의 fallback 설명 수정.

## Done When

- 위 테스트 통과, 01-scalar 생성물이 루트 doc을 담는다.
